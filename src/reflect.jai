#import "Compiler";
#import "Math";
#import "String";



// TODO Turn polymorph args into ReflectorFlags, most likely
Reflector :: struct (ReflectedTypeInfo: $T, $IsReading: bool, $SupportsPackedTypes: bool = false)
{
    IsWriting :: !IsReading;

    error: ReflectResult = .Ok;
}

ReflectResult :: enum
{
    Ok;
    BadData;
    Overflow;
    InvalidSchema;

    SomeError;
}

// TODO Store the code location of the piece of data causing the error
SetError :: ( error: ReflectResult, r: *Reflector )
{
    // Only remember the first error location
    if r.error != .Ok
        r.error = error;
}



StructNodeIdentFor :: ( ti: *Type_Info, endStatement: bool ) -> string #compile_time
{
    // Use the actual hex address as part of the identifier
    if endStatement
        return tprint( "_struct_node_%;", ti );
    else
        return tprint( "_struct_node_%", ti );
}

FindMemberDecl :: ( m: Type_Info_Struct_Member, members: [] *Code_Scope_Entry ) -> *Code_Declaration
{
    for members
    {
        assert( it.kind == .DECLARATION );
        decl := cast(*Code_Declaration) it;
        if equal( decl.name, m.name )
            return decl;
    }
    return null;
}

FieldArgs :: struct
{
    name: string;
    value: Any;
}
// NOTE All notes can be written as specified or with a 'reflect_' prefix before the given name
// NOTE Returns a temporary args array
// TODO Convert string args based on names & types array
// TODO Extract to bricks
ParseNote :: ( noteName: string, notes: [] *Code_Note, argNames: [] string = .[], argTypes: [] Type = .[] ) -> noteIndex: int, args: []string
{
    assert( argNames.count == argTypes.count );

    name := noteName;
    prefixedName := tprint( "reflect_%", name );

    for notes
    {
        noteStr := it.text;
        found := false;

        if starts_with( noteStr, name )
            found = true;
        else if starts_with( noteStr, prefixedName )
        {
            found = true;
            name = prefixedName;
        }

        if found
        {
            // Does it have any arguments
            if noteStr.count > name.count && noteStr[name.count] == #char "("
            {
                // TODO Improve reporting of malformed arg expressions
                // Get substring up until closing parens
                argsFound, argString, _ := split_from_left( slice( noteStr, name.count + 1, noteStr.count ), #char ")" );
                if !argsFound
                    return -1, .[];

                // Parse args as comma separated strings
                // Weird cast required to get the 'fast' single char overload
                // New 'context arguments' make it look even prettier
                args := split( argString, cast(u8) #char ",",, allocator = temp );
                return it_index, args;
            }
            else
                return it_index, .[];
        }
    }
    return -1, .[];
}

FieldFlags :: enum_flags u8
{
    Packed;
}
ReflectedFieldInfo :: struct
{
    decl: *Code_Declaration;
    //args: [..] FieldArgs;
    id: u16;
    name: string;
    flags: FieldFlags;
}

ReflectedTypeInfo :: struct
{
    location: Source_Code_Location;
    // Contains all the struct's members, not just the annotated ones
    fieldInfo: [] ReflectedFieldInfo;
    annotatedFieldCount: s32;
    maxId: u16;
    isPacked: bool;
}
Init :: ( using sti: *ReflectedTypeInfo, memberCount: int )
{
    fieldInfo = NewArray( memberCount, ReflectedFieldInfo );
}
Destroy :: ( using sti: *ReflectedTypeInfo )
{
    free( fieldInfo.data );
    << sti = .{};
}

// TODO Should probably cache all these calls in a hashtable
GatherReflectedTypeInfo :: ( st: *Type_Info_Struct, stNode: *Code_Struct ) -> bool, ReflectedTypeInfo #compile_time
{
    result: ReflectedTypeInfo;
    Init( *result, st.members.count );
    result.location = make_location( stNode );

    // First of all, check if this type was marked as 'packed'
    packedNoteIdx, _ := ParseNote( "packed", stNode.notes );
    result.isPacked = packedNoteIdx != -1;

    // Parse all field notes & their arguments, and populate a (decl-order?) array with all the info
    // TODO Special processing for constants (negative offset_in_bytes), usings, procedures? etc
    // TODO TODO Check discovered layout against a persisted one from last compilation
    // TODO When writing, *always order by offset in the source struct type* for cache friendliness
    // TODO When reading, the stream tells us the order of members to write to, but assume memory order too
    for m, index: st.members
    {
        info := *result.fieldInfo[index];
        info.name = m.name;

        decl := FindMemberDecl( m, stNode.block.members );
        assert( decl != null, "Couldn't find member decl node for '%'\n", m.name );
        info.decl = decl;

        // Parse field id
        fieldNoteIdx, fieldNoteArgs := ParseNote( "field", decl.notes );
        if fieldNoteIdx != -1
        {
            if !fieldNoteArgs
            {
                // TODO This is also way too verbose for my liking, and imo any metaprogram errors should be annotated by which metaprogram emitted them!
                compiler_report( "'field' note requires a u16 'id' argument (in parenthesis)", make_location( decl.notes[fieldNoteIdx] ) );
                return false, result;
            }

            // NOTE string_to_int does not currently check for overflows if a small type is specified
            fieldId, idOk, _ := string_to_int( fieldNoteArgs[0], 10 );
            if !idOk
            {
                compiler_report( "Unable to parse field 'id' argument into a u16", make_location( decl.notes[fieldNoteIdx] ) );
                return false, result;
            }
            else if fieldId <= 0
            {
                compiler_report( "Field 'id' must be a positive (non-zero) integer", make_location( decl.notes[fieldNoteIdx] ) );
                return false, result;
            }
            else if fieldId > U16_MAX
            {
                compiler_report( "Field 'id' argument is too big", make_location( decl.notes[fieldNoteIdx] ) );
                return false, result;
            }

            info.id = cast(u16)fieldId;
            result.maxId = Max( result.maxId, info.id );
            // TODO Parse optional name attribute etc.

            result.annotatedFieldCount += 1;
        }

        // Check if this is a 'packed' struct type
        // TODO There is currently no way to pass on this information to the Reflect() function for the subtype
        // so it's not clear we can support this!?
        if m.type.type == .STRUCT
        {
            fieldStructType  := cast(*Type_Info_Struct) m.type;
            if Contains( fieldStructType.notes, "packed" )
                info.flags |= .Packed;
        }
    }

    // If there were no annotations, simply assign a memory-order index as field id
    if result.annotatedFieldCount == 0
    {
        lastOffset := -1;
        for m, index: st.members
        {
            info := *result.fieldInfo[index];

            // Not sure if there's any guarantees about the order of the entries in the members array
            // so assert that we're always increasing the offset inside the parent struct
            // TODO Assert macro that prints the expression and an optional msg!
            assert( m.offset_in_bytes > lastOffset && "We assume in-memory order of members!" );
            // FIXME This breaks with overlapped fields (unions)
            lastOffset = m.offset_in_bytes;

            assert( info.id == 0 );
            info.id = cast(u16)(index + 1);
        }
        // In this case, all fields are (auto) annotated
        result.annotatedFieldCount = cast(s32) st.members.count;
        result.maxId = cast(u16) st.members.count;
    }

    return true, result;
}

// FIXME #no_reset doesnt work at all with stuff that allocates!
GenStaticTypeInfo :: ( stNodes: [] *Code_Struct ) #compile_time
{
    for stNodes
    {
        print( "%\n", it.defined_type.name );

        ok, info := GatherReflectedTypeInfo( it.defined_type, it );
        assert( ok, "GatherReflectedTypeInfo failed for %", it.defined_type );

        table_set( *globalStructTypeInfoTable, it.defined_type, info );
    }

    // Can't have spaces in notes!
} @runAfterTypechecking(globalReflectedStructNodes)


#scope_module

#import "Hash_Table";

globalBuilder: String_Builder;

// NOTE Remember! Only structs for which we're calling Reflect() will appear here!
#placeholder globalReflectedStructNodes;
#no_reset globalStructTypeInfoTable: Table(*Type_Info_Struct, ReflectedTypeInfo);


GenReflectFunction :: ( T: Type, st: *Type_Info_Struct, reflector: $Reflector ) -> string #expand #compile_time
{
    defer free_buffers( *globalBuilder );

    // Find the code node for the given type declaration, so we can access exact source code locations for error reporting
    // I haven't found any way to reliably find the nodes for the struct type declaration given just the type info,
    // so we emit them from the metaprogram and place them in a constant with a known name for each type
    stNode :: #insert #run StructNodeIdentFor( type_info(T), true );
    assert( stNode != null, "Code node for type '%' not available", st.name );

    // For runtime code, we also gather all these nodes and generate the ReflectedTypeInfo for each of them,
    // and index that in globalStructTypeInfoTable. However, here at compile time, the #run directive that
    // builds that table may not have run yet, so we just go gather that info again..
    ok, info := GatherReflectedTypeInfo( st, stNode );
    if !ok
        return "";

    isPacked := false;
    #if reflector.SupportsPackedTypes
    {
        // TODO Unions (seem to be accepted by the struct interface too)
        if info.isPacked
        {
            append( *globalBuilder, "    return inline ReflectPacked( d, r );\n" );
            isPacked = true;
        }
    }

    if !isPacked
    {
        // If no member fields have been identified, and this is not a 'packed' struct, default to in-memory-order consecutive automatic ids,
        // so that if the user decides in the future he wants to change the default, old data can still be read
        if false //info.annotatedFieldCount == 0
        {
            // TODO All warnings should go to a file by default probably?
            ReportWarning( info.location,
                           "Structured type '%' will be serialised but has no serialisation notes. Will default to memory-order fields.",
                           st.name );
        }

        // TODO Perhaps by default we should embed the existing ReflectedTypeInfo inside the custom reflector's ReflectedTypeInfo?
        append( *globalBuilder, "    info: r.ReflectedTypeInfo;\n" );
        append( *globalBuilder, tprint( "    if BeginReflectType( *info, %, r )\n", st.name ) );
        append( *globalBuilder, "    {\n" );
        append( *globalBuilder, "        defer EndReflectType( *info, r );\n" );
        append( *globalBuilder, "        \n" );

        for m, index: st.members
        {
            fieldInfo := *info.fieldInfo[index];
            if fieldInfo.id
            {
                append( *globalBuilder, tprint( "        ReflectField( *d.%, %, \"%\", %, *info, r );\n",
                                                m.name, fieldInfo.id, m.name, m.offset_in_bytes ) );
            }
        }

        append( *globalBuilder, "    }\n" );
        // TODO Test that this correctly returns any errors set in EndReflectType
        append( *globalBuilder, "    return r.error;\n" );
    }

    return builder_to_string( *globalBuilder );
}


#scope_export

// Generate a separate polymorph instance and its corresponding body based on the type it was called with.
// This way we only generate the overloads that are actually called from user code.
// This signature seems to allow creating a specific overload for structs without using #modify
// TODO When writing, *always order by offset in the source struct type* for cache friendliness
// TODO When reading, the stream tells us the order of members to write to, which probably means the function body is the same
// for all types, and we just HAVE TO do dynamic dispatch? Although, we can have a (compiletime) table of field id to member typeinfo
// and recover a typed pointer to the member doing something like:
                //M := get_root_type( m.type );
                //Reflect( GetMemberValueAs( m, d, M ), r );
Reflect :: ( d: *$T/interface struct {}, r: *$Reflector ) -> ReflectResult
{
    // TODO Doing things this way means a new #run happens everytime we invoke this function, hence the same code is inserted more than once
    // So we probably want to keep a chached mapping of type_info to generated string
    // (for the 'production-ready' generators we need this anyway to generate the type descriptor tables)
    // Note that according to how_to 100 though, this #run should only be invoked once for each type we pass in $T
    // Do we see two because we pass both a reader and a writer in r for each type?
    #insert #run GenReflectFunction( T, type_info( T ), type_of( r ) );
}

// TODO When benchmarking, test making a custom overload for BinaryReflectors that tries to streamline this as much as possible
// NOTE Apparently there's a limit to macro recursion .. https://github.com/Jai-Community/Jai-Community-Library/wiki/Getting-Started#nested-macros
// As demonstrated, we can refer to the constants block of the type of a declared argument to declare a separate argument, like with
// ReflectedTypeInfo here, which is freaking awesome!
ReflectField :: ( field: Code, fieldId: u16, name: string, offsetBytes: s64, info: *r.ReflectedTypeInfo, r: *$Reflector ) #expand
{
    result: ReflectResult = .Ok;

    //fieldOffset := ReflectFieldOffset( r );      
    if BeginReflectField( fieldId, name, offsetBytes, info, r )  // attribs ) )
    {                                                     
        result = Reflect( #insert field, r );                        

        EndReflectField( fieldId, info, r );  // fieldOffset
    }

    if result != .Ok
    {
        SetError( result, r );
        // Return from outer Reflect() function
        `return result;
    }
}


