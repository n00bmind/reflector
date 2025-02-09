
DeepEquals :: ( a: Any, b: Any ) -> bool
{
    errorStr: String_Builder;
    errorStr.allocator = temp;

    // TODO Would like to print the type name here
    // scope := a.type.name;
    result := DeepEqualsInternal( cast(*Any_Struct) *a, cast(*Any_Struct) *b, "<root>", *errorStr );
    if !result
    {
        // TODO log_debug
        log( "%\n", builder_to_string( *errorStr ) );
        free_buffers( *errorStr );
    }
    return result;
}

DeepEqualsInternal :: ( a: *Any_Struct, b: *Any_Struct, scope: string, errorStr: *String_Builder ) -> bool
{
    if a.type != b.type
    {
        print_to_builder( errorStr, ".type - Types differ (a is %, b is %)", a.type, b.type );
        return false;
    }

    builderState: struct
    {
        currentBuffer: *String_Builder.Buffer;
        currentBufferCount: s64;
    }
    // Save current state in the stack
    builderState.currentBuffer = get_current_buffer( errorStr );
    builderState.currentBufferCount = builderState.currentBuffer.count;

    append( errorStr, scope );

    if a.type.type ==
    {
        case .STRUCT;
        {
            aType := cast(*Type_Info_Struct) a.type;
            for aType.members
            {
                aIt := Any_Struct.{ it.type, a.value_pointer + it.offset_in_bytes };
                bIt := Any_Struct.{ it.type, b.value_pointer + it.offset_in_bytes };

                scope := tprint( ".%", it.name );
                result := DeepEqualsInternal( *aIt, *bIt, scope, errorStr );
                if !result
                    return false;
            }
        }
        case .ARRAY;
        {
            aType := cast(*Type_Info_Array) a.type;
            bType := cast(*Type_Info_Array) b.type;
            itType := aType.element_type;

            aBase, bBase: *void = null;
            aCount, bCount: s64 = 0;
            if aType.array_type ==
            {
                case .FIXED;
                    aBase = a.value_pointer;
                    bBase = b.value_pointer;
                    aCount = aType.array_count;
                    bCount = bType.array_count;
                case .VIEW;
                    aArray := cast(*Array_View_64) a.value_pointer;
                    bArray := cast(*Array_View_64) b.value_pointer;
                    aBase = aArray.data;
                    bBase = bArray.data;
                    aCount = aArray.count;
                    bCount = bArray.count;
                case .RESIZABLE;
                    aArray := cast(*Resizable_Array) a.value_pointer;
                    bArray := cast(*Resizable_Array) b.value_pointer;
                    aBase = aArray.data;
                    bBase = bArray.data;
                    aCount = aArray.count;
                    bCount = bArray.count;
            }

            if aCount != bCount
            {
                print_to_builder( errorStr, ".count - Counts differ (a is %, b is %)", aCount, bCount );
                return false;
            }
            for idx: 0 .. aCount - 1
            {
                aIt := Any_Struct.{ itType, aBase + idx * itType.runtime_size };
                bIt := Any_Struct.{ itType, bBase + idx * itType.runtime_size };
                scope := tprint( ".[%]", idx );
                result := DeepEqualsInternal( *aIt, *bIt, scope, errorStr );
                if !result
                    return false;
            }
        }
        case .STRING;
        {
            aString := cast(*string) a.value_pointer;
            bString := cast(*string) b.value_pointer;
            result := <<aString == <<bString;
            if !result
            {
                print_to_builder( errorStr, " - Strings differ (a is '%', b is '%')", <<aString, <<bString );
                return false;
            }
        }
        case;
        {
            // Simply memcmp their bytes
            result := memcmp( a.value_pointer, b.value_pointer, a.type.runtime_size ) == 0;
            if !result
            {
                print_to_builder( errorStr, " - Bit contents differ (compared % bytes)", a.type.runtime_size );
                return false;
            }
        }
    }

    // Rewind current error path by restoring the builder's state
    errorStr.current_buffer = builderState.currentBuffer;
    errorStr.current_buffer.count = builderState.currentBufferCount;

    return true;
}


// TODO Most of this stuff can surely be module scope?

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

// NOTE All notes can be written as specified or with a 'reflect_' prefix before the given name
// NOTE Returns a temporary args array
// TODO Convert string args based on names & types array
// TODO Extract to bricks
ParseNote :: ( noteName: string, notes: [] string, argNames: [] string = .[], argTypes: [] Type = .[] ) -> noteIndex: int, args: []string
{
    assert( argNames.count == argTypes.count );

    name := noteName;
    prefixedName := tprint( "reflect_%", name );

    for notes
    {
        noteStr := it;
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

FieldArgs :: struct
{
    name: string;
    value: Any;
}
FieldFlags :: enum_flags u8
{
    Packed;
}
ReflectedFieldInfo :: struct
{
    //args: [..] FieldArgs;
    name: string;
    offset: s32;
    id: u16;
    flags: FieldFlags;
}

ReflectedTypeInfo :: struct
{
    location: Source_Code_Location;
    // Contains all the struct's members, not just the annotated ones, in memory order
    fieldInfo: [] ReflectedFieldInfo;
    annotatedFieldCount: u16;
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

FindFieldInfo :: ( id: u16, typeInfo: ReflectedTypeInfo ) -> *ReflectedFieldInfo
{
    if id > typeInfo.maxId
        return null;

    for * typeInfo.fieldInfo
    {
        if it.id == id
            return it;
    }
    return null;
}

// TODO Cache results in a hashtable so we only do this for each type the first time
GatherReflectedTypeInfo :: ( st: *Type_Info_Struct, stLocation: Source_Code_Location = .{} ) -> bool, ReflectedTypeInfo #compile_time
{
    result: ReflectedTypeInfo;
    Init( *result, st.members.count );

    if !stLocation.fully_pathed_filename
        stLocation = compiler_get_struct_location( get_current_workspace(), st );
    // TODO log_debug
    // log_debug( "(note) Struct % was defined in % (workspace %)\n", st.name, stLocation, get_current_workspace() );
    result.location = stLocation;

    // First of all, check if this type was marked as 'packed'
    packedNoteIdx, _ := ParseNote( "packed", st.notes );
    result.isPacked = packedNoteIdx != -1;

    // Parse all field notes & their arguments, and populate a (decl-order?) array with all the info
    // TODO Special processing for constants (negative offset_in_bytes), usings, procedures? etc
    // TODO Check discovered layout against a persisted one from last compilation
    // TODO When writing, *always order by offset in the source struct type* for cache friendliness
    // TODO When reading, the stream tells us the order of members to write to, but assume memory order too
    for m, index: st.members
    {
        info := *result.fieldInfo[index];
        info.name = m.name;

        // decl := FindMemberDecl( m, stNode.block.members );
        // assert( decl != null, "Couldn't find member decl node for '%'\n", m.name );
        // info.decl = decl;

        // Parse field id
        fieldNoteIdx, fieldNoteArgs := ParseNote( "field", m.notes );
        if fieldNoteIdx != -1
        {
            if !fieldNoteArgs
            {
                msg := tprint( "In declaration of field '%': 'field' note requires a u16 'id' argument (in parenthesis)", m.name );
                // TODO This is also way too verbose for my liking, and imo any metaprogram errors should be annotated by which metaprogram emitted them!
                compiler_report( msg, stLocation );
                return false, result;
            }

            // NOTE string_to_int does not currently check for overflows if a small type is specified
            fieldId, idOk, _ := string_to_int( fieldNoteArgs[0], 10 );
            if !idOk
            {
                msg := tprint( "In declaration of field '%': Unable to parse field 'id' argument into a u16", m.name );
                compiler_report( msg, stLocation );
                return false, result;
            }
            else if fieldId <= 0
            {
                msg := tprint( "In declaration of field '%': Field 'id' must be a positive (non-zero) integer", m.name );
                compiler_report( msg, stLocation );
                return false, result;
            }
            else if fieldId > U16_MAX
            {
                msg := tprint( "In declaration of field '%': Field 'id' argument is too big", m.name );
                compiler_report( msg, stLocation );
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
            info.offset = cast(s32)m.offset_in_bytes;
        }
        // In this case, all fields are (auto) annotated
        result.annotatedFieldCount = cast(u16) st.members.count;
        // Valid ids start at 1
        result.maxId = cast(u16) st.members.count;
    }

    return true, result;
}

// TODO Not needed anymore?
// FIXME #no_reset doesnt work at all with stuff that allocates!
GenStaticTypeInfo :: ( stNodes: [] *Code_Struct ) #compile_time
{
    for stNodes
    {
        print( "%\n", it.defined_type.name );

        ok, info := GatherReflectedTypeInfo( it.defined_type, make_location( it ) );
        assert( ok, "GatherReflectedTypeInfo failed for %", it.defined_type );

        table_set( *globalStructTypeInfoTable, it.defined_type, info );
    }

    // Can't have spaces in notes!
} @runAfterTypechecking(globalReflectedStructNodes)


IsPrimitiveType :: inline ( ti: *Type_Info ) -> bool
{
    return ti.type == .INTEGER || ti.type == .FLOAT || ti.type == .BOOL || ti.type == .ENUM;
}
IsPrimitiveType :: inline ( $T: Type ) -> bool
{
    return IsPrimitiveType( cast(*Type_Info) T );
}

// TODO We should be able to make these 'constexpr/eval' functions, but how does one do that in Jai?
// May be a good Q for the next Q&A
IsArrayType :: inline ( $T: Type ) -> bool
{
    ti := cast(*Type_Info) T;
    return ti.type == .ARRAY || ti.type == .STRING;
}

IsFixedArrayType :: inline ( $T: Type ) -> bool
{
    ti := cast(*Type_Info) T;
    if ti.type != .ARRAY
        return false;
    tia := cast(*Type_Info_Array) T;
    return tia.array_type == .FIXED;
}

IsPrimitiveArrayType :: inline ( $T : Type ) -> bool
{
    ti := cast(*Type_Info) T;

    if ti.type == .STRING
        return true;

    if ti.type != .ARRAY
        return false;

    tia := cast(*Type_Info_Array) ti;
    return IsPrimitiveType( tia.element_type );
}


// Utility procs to always ensure we're not trying to read past the end of the buffer
// If you call these with an exhausted buffer, no copy will occur, and the bufferHead will remain at buffer.count
// TODO Ideally we'd probably want to make these non polymorphic on r (or even completely)
// TODO Compiler bug! Using 'using r' in these causes size_of(T) to always return 8
Read :: inline ( r: *Reflector, d: *$T )
{
    bytesToCopy := min( size_of(T), r.buffer.count - r.bufferHead );
    Copy( r.buffer.data + r.bufferHead, d, bytesToCopy );
}

Read :: inline ( r: *Reflector, d: *$T, offset: s64 )
{
    bytesToCopy := min( size_of(T), r.buffer.count - offset );
    Copy( r.buffer.data + offset, d, bytesToCopy );
}

// TODO How can we make these faster
ReadAndAdvance :: inline ( r: *Reflector, d: *$T )
{
    bytesToCopy := min( size_of(T), r.buffer.count - r.bufferHead );
    Copy( r.buffer.data + r.bufferHead, d, bytesToCopy );
    r.bufferHead += bytesToCopy;
}

ReadAndAdvance :: inline ( r: *Reflector, d: [] u8 )
{
    bytesToCopy := min( d.count, r.buffer.count - r.bufferHead );
    Copy( r.buffer.data + r.bufferHead, d.data, bytesToCopy );
    r.bufferHead += bytesToCopy;
}

ReadAndAdvance :: inline ( r: *Reflector, d: [] $T )
{
    dSize := d.count * size_of(T);
    bytesToCopy := min( dSize, r.buffer.count - r.bufferHead );
    Copy( r.buffer.data + r.bufferHead, d.data, bytesToCopy );
    r.bufferHead += bytesToCopy;
}

Advance :: inline ( r: *Reflector, sizeBytes: s64 )
{
    bytesToSkip := min( sizeBytes, r.buffer.count - r.bufferHead );
    r.bufferHead += bytesToSkip;
}

SetBufferHead :: inline ( r: *Reflector, offsetBytes: s64 )
{
    newOffset := min( offsetBytes, r.buffer.count );
    r.bufferHead = newOffset;
}

#scope_module

#import "Basic";
#import "String";
#import "Math";
#import "Hash_Table";
#import "Compiler";

globalBuilder: String_Builder;

// TODO Not needed anymore?
// NOTE Remember! Only structs for which we're calling Reflect() will appear here!
#placeholder globalReflectedStructNodes;
#no_reset globalStructTypeInfoTable: Table(*Type_Info_Struct, ReflectedTypeInfo);


#scope_export

GenReflectFunction :: ( T: Type, st: *Type_Info_Struct, R: Type ) -> string #expand #compile_time
{
    defer free_buffers( *globalBuilder );

    // Find the code node for the given type declaration, so we can access exact source code locations for error reporting
    // I haven't found any way to reliably find the nodes for the struct type declaration given just the type info,
    // so we emit them from the metaprogram and place them in a constant with a known name for each type
    // TODO This entirely eliminates the possibility of using this reflection system from a user's metaprogram!
    // stNode :: #insert #run StructNodeIdentFor( type_info(T), true );
    // assert( stNode != null, "Code node for type '%' not available", st.name );

    // For runtime code, we also gather all these nodes and generate the ReflectedTypeInfo for each of them,
    // and index that in globalStructTypeInfoTable. However, here at compile time, the #run directive that
    // builds that table may not have run yet, so we just go gather that info again..
    ok, info := GatherReflectedTypeInfo( st );
    if !ok
        return "";

    append( *globalBuilder, tprint( "    // Body of Reflect( *%, *% )\n", T, R ) );

    isPacked := false;
    // TODO Consider making all other customizable bits in Reflectors (including functions like Begin/EndReflectType etc.) be constants
    // declared in the struct like this, so we can reason about them at compile time and skip unnecessary bits entirely for Reflectors
    // that dont need them
    #if R.SupportsPackedTypes
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
            // TODO This is not even a warning, more like an "info"
            ReportWarning( info.location,
                           "Structured type '%' will be serialised but has no serialisation notes. Will default to memory-order fields.",
                           st.name );
        }

        // TODO Perhaps by default we should embed the existing ReflectedTypeInfo inside the custom reflector's ReflectedTypeInfo?
        append( *globalBuilder, "    info: r.ReflectedTypeInfo;\n" );
        append( *globalBuilder, "    if BeginReflectType( *info, T, r )\n" );
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


#scope_module

// Generate a separate polymorph instance and its corresponding body based on the type it was called with.
// This way we only generate the overloads that are actually called from user code.
// TODO When writing, *always order by offset in the source struct type* for cache friendliness
// TODO When reading, the stream tells us the order of members to write to, which probably means the function body is the same
// for all types, and we just HAVE TO do dynamic dispatch? Although, we can have a (compiletime) table of field id to member typeinfo
// and recover a typed pointer to the member doing something like:
                //M := get_root_type( m.type );
                //Reflect( GetMemberValueAs( m, d, M ), r );

REFLECT_STUBS :: #string STR

// TODO When benchmarking, test making a custom overload for BinaryReflectors that tries to streamline this as much as possible
// NOTE Apparently there's a limit to macro recursion .. https://github.com/Jai-Community/Jai-Community-Library/wiki/Getting-Started#nested-macros
// As demonstrated, we can refer to the constants block of the type of a declared argument to declare a separate argument, like with
// ReflectedTypeInfo here, which is freaking awesome!
ReflectField :: ( field: Code, fieldId: u16, name: string, offsetBytes: s64, info: *r.ReflectedTypeInfo, r: *$R ) #expand
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

STR

