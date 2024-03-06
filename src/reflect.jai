#import "Compiler";
#import "Bucket_Array";
#import "Math";
#import "String";

#load "basic.jai";
#load "datatypes.jai";


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

    SomeError;
}

// TODO Store the code location of the piece of data causing the error
SetError :: ( error: ReflectResult, r: *Reflector )
{
    // Only remember the first error location
    if r.error != .Ok
        r.error = error;
}


globalBuilder: String_Builder;

// #insert #run this FROM COMPILE-TIME
// TODO Probably should be cached / deduplicated?
// TODO Extract to bricks
// FIXME This has some "visibility issues" with non-globally defined types
GetCodeNodesFor :: ( ident: string ) -> string #compile_time
{
    return tprint( "compiler_get_nodes( % );\n", ident );
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
ParseNote :: ( noteName: string, notes: [] *Code_Note, argNames: [] string = .[], argTypes: [] Type = .[] ) -> noteFound: bool, args: []string
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
                    return false, .[];

                // Parse args as comma separated strings
                // Weird cast required to get the 'fast' single char overload
                // New 'context arguments' make it look even prettier
                args := split( argString, cast(u8) #char ",",, allocator = temp );
                return true, args;
            }
            else
                return true, .[];
        }
    }
    return false, .[];
}

FieldFlags :: enum_flags u8
{
    Packed;
}
FieldInfo :: struct
{
    //member: *Type_Info_Struct_Member;
    decl: *Code_Declaration;
    //args: [..] FieldArgs;
    id: u16;
    name: string;
    flags: FieldFlags;
}

GenReflectFunction :: ( T: Type, st: *Type_Info_Struct, reflector: $ReflectorType, w: Workspace = -1 ) -> string #expand #compile_time
{
    defer free_buffers( *globalBuilder );

    // Find the code node for the given type declaration, so we can access exact node locations for error reporting
    // Can't use 'st.name' here, as that'd require a closure
    // TODO Actually check second return value for ambiguities etc
    rootNode, _ := #insert #run GetCodeNodesFor( type_info(T).name );
    assert( rootNode.kind == .IDENT );

    rootDecl := (cast(*Code_Ident) rootNode).resolved_declaration;
    exprNode := rootDecl.expression;
    assert( exprNode.kind == .STRUCT, "Reflected expression node should be a .STRUCT (got %)\n", exprNode.kind );

    stNode := cast(*Code_Struct) exprNode;
    assert( stNode.defined_type == st, "Defined type in reflected expression doesn't match given type (wanted %, got %)\n", st, stNode.defined_type );


    // First of all, check if this type was marked as 'packed'
    isPacked := false;
    #if reflector.SupportsPackedTypes
    {
        packedFound, packedArgs := ParseNote( "packed", rootDecl.notes );
        isPacked = packedFound;
    }

    // TODO Unions (seem to be accepted by the struct interface too)
    if isPacked
        append( *globalBuilder, "    return inline ReflectPacked( d, r );\n" );
    else
    {
        annotatedFieldCount := 0;
        // Do a first pass parsing notes & their arguments, and populate a (decl-order?) array with all the info
        // TODO Special processing for constants (negative offset_in_bytes), usings, procedures? etc
        // TODO TODO Check discovered layout against a persisted one from last compilation
        // TODO When writing, *always order by offset in the source struct type* for cache friendliness
        // TODO When reading, the stream tells us the order of members to write to, but assume memory order too
        fieldInfo: [] FieldInfo = NewArray( st.members.count, FieldInfo );
        for m, index: st.members
        {
            info := *fieldInfo[index];
            //info.member = m;

            decl := FindMemberDecl( m, stNode.block.members );
            assert( decl != null, "Couldn't find member decl node for '%'\n", m.name );
            info.decl = decl;

            // Parse field id
            fieldFound, fieldArgs := ParseNote( "field", decl.notes );
            if !fieldFound
                // This guy is not marked for serialization
                continue;

            if !fieldArgs
            {
                // TODO This is also way too verbose for my liking, and imo any metaprogram errors should be annotated by which metaprogram emitted them!
                compiler_report( "'field' note requires a u16 'id' argument (in parenthesis)", compiler_get_struct_location( w, st ) );
                return "";
            }

            // NOTE string_to_int does not currently check for overflows if a small type is specified
            fieldId, idOk, _ := string_to_int( fieldArgs[0], 10 );
            if !idOk
            {
                compiler_report( "Unable to parse field 'id' argument into a u16", compiler_get_struct_location( w, st ) );
                return "";
            }
            else if fieldId <= 0
            {
                compiler_report( "Field 'id' must be a positive (non-zero) integer", compiler_get_struct_location( w, st ) );
                return "";
            }
            else if fieldId > U16_MAX
            {
                compiler_report( "Field 'id' argument is too big", compiler_get_struct_location( w, st ) );
                return "";
            }

            info.id = cast(u16)fieldId;

            // Check if this is a 'packed' struct type
            // TODO If fieldArgs contain the 'packed' flag already, then we don't need to do this..
            if m.type.type == .STRUCT
            {
                fieldStructType  := cast(*Type_Info_Struct) m.type;
                if Contains( fieldStructType.notes, "packed" )
                    info.flags |= .Packed;
            }

            // TODO Parse optional name attribute etc.

            annotatedFieldCount += 1;
        }

        // If no member fields have been identified, and this is not a 'packed' struct, default to in-memory-order consecutive automatic ids,
        // so that if the user decides in the future he wants to change the default, old data can still be read
        if annotatedFieldCount == 0
        {
            ReportWarning( make_location( rootDecl ),
                            "Structured type '%' will be serialised but has no serialisation notes. Will default to memory-order fields.",
                            st.name );
        }

        append( *globalBuilder, "    info: r.ReflectedTypeInfo;\n" );
        append( *globalBuilder, tprint( "    if BeginReflectType( *info, %, r )\n", st.name ) );
        append( *globalBuilder, "    {\n" );
        append( *globalBuilder, "        defer EndReflectType( *info, r );\n" );
        append( *globalBuilder, "        \n" );

        lastOffset := -1;
        for m, index: st.members
        {
            info := *fieldInfo[index];
            // If there were no annotations, simply assign a memory-order index as field id
            if annotatedFieldCount == 0
            {
                // Not sure if there's any guarantees about the order of the entries in the members array
                // so assert that we're always increasing the offset inside the parent struct
                // TODO Assert macro that prints the expression and an optional msg!
                assert( m.offset_in_bytes > lastOffset && "We assume in-memory order of members!" );
                // FIXME This breaks with overlapped fields (unions)
                lastOffset = m.offset_in_bytes;

                assert( info.id == 0 );
                info.id = cast(u16)(index + 1);
            }

            if info.id
            {
                append( *globalBuilder, tprint( "        ReflectField( *d.%, %, \"%\", %, *info, r );\n",
                                                m.name, info.id, m.name, m.offset_in_bytes ) );
            }
        }

        append( *globalBuilder, "    }\n" );
        // TODO Test that this correctly returns any errors set in EndReflectType
        append( *globalBuilder, "    return r.error;\n" );
    }

    return builder_to_string( *globalBuilder );
}

// Generate a separate polymorph instance and its corresponding body based on the type it was called with.
// This way we only generate the overloads that are actually called from user code.
// This signature seems to allow creating a specific overload for structs without using #modify
// TODO When writing, *always order by offset in the source struct type* for cache friendliness
// TODO When reading, the stream tells us the order of members to write to, which probably means the function body is the same
// for all types, and we just HAVE TO do dynamic dispatch? Although, we can have a (compiletime) table of field id to member typeinfo
// and recover a typed pointer to the member doing something like:
                //M := get_root_type( m.type );
                //Reflect( GetMemberValueAs( m, d, M ), r );
Reflect :: ( d: *$T/interface struct {}, r: *Reflector ) -> ReflectResult
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
ReflectField :: ( field: Code, fieldId: u16, name: string, offsetBytes: s64, info: *r.ReflectedTypeInfo, r: *Reflector ) #expand
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


