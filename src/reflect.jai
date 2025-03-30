
// TODO Turn polymorph args into ReflectorFlags, where appropriate
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


GenReflectFunction :: ( T: Type, st: *Type_Info_Struct, R: Type ) -> string #expand #compile_time
{
    builder: String_Builder;
    builder.allocator = temp;

    // Build ReflectedTypeInfo for this type, based on all the notes and metadata
    ok, info := GatherReflectedTypeInfo( st );
    if !ok
        return "";

    append( *builder, tprint( "    // Body of Reflect( *%, % )\n", T, R ) );

    isPacked := false;
    // TODO Consider making all other customizable bits in Reflectors (including functions like Begin/EndReflectType etc.) be constants
    // declared in the struct like this, so we can reason about them at compile time and skip unnecessary bits entirely for Reflectors
    // that dont need them
    #if R.SupportsPackedTypes
    {
        // TODO Unions (seem to be accepted by the struct interface too)
        if info.isPacked
        {
            append( *builder, "    return inline ReflectPacked( d, r );\n" );
            isPacked = true;
        }
    }

    if !isPacked
    {
        // If no member fields have been identified, and this is not a 'packed' struct, default to in-memory-order consecutive automatic ids,
        // so that if the user decides in the future he wants to change the default, old data can still be read
        if info.annotatedFieldCount == 0
        {
            // TODO Show this only in a "verbose" mode perhaps?
            ReportNote( info.location,
                        "Struct type '%' will be serialised but has no serialisation notes. Will default to memory-order fields.",
                        st.name );
        }

        // TODO Perhaps by default we should embed the existing ReflectedTypeInfo inside the custom reflector's ReflectedTypeInfo
        // so that info is available to the Reflector code?
        append( *builder, "    info: r.ReflectedTypeInfo;\n" );
        append( *builder, "    if BeginReflectType( *info, T, r )\n" );
        append( *builder, "    {\n" );
        append( *builder, "        defer EndReflectType( *info, r );\n" );
        append( *builder, "        \n" );

        for m, index: st.members
        {
            fieldInfo := *info.fieldInfo[index];
            if fieldInfo.id
            {
                append( *builder, tprint( "        ReflectField( *d.%, %, \"%\", %, *info, r );\n",
                                                m.name, fieldInfo.id, m.name, m.offset_in_bytes ) );
            }
        }

        append( *builder, "    }\n" );
        // TODO Test that this correctly returns any errors set in EndReflectType
        append( *builder, "    return r.error;\n" );
    }

    return builder_to_string( *builder );
}

// TODO Cache results in a hashtable so we only do this for each type the first time
GatherReflectedTypeInfo :: ( st: *Type_Info_Struct, stLocation: Source_Code_Location = .{} ) -> bool, ReflectedTypeInfo #compile_time
{
    result: ReflectedTypeInfo;
    Init( *result, st.members.count );

    if !stLocation.fully_pathed_filename
        stLocation = compiler_get_struct_location( get_current_workspace(), st );
    result.location = stLocation;

    // First of all, check if this type was marked as 'packed'
    packedNoteIdx, _ := ParseNote( "packed", st.notes );
    result.isPacked = packedNoteIdx != -1;

    // Parse all field notes & their arguments, and populate a (decl-order?) array with all the info
    // TODO Special processing for constants (negative offset_in_bytes), usings, procedures? etc
    // TODO Check discovered layout against a persisted one from last compilation
    for m, index: st.members
    {
        info := *result.fieldInfo[index];
        info.name = m.name;

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

            // string_to_int does not currently check for overflows if a small type is specified, so we need to do it ourselves
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


// Other type-inspection utilities
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
IsIntegralType :: inline ( $T: Type ) -> bool
{
    ti := cast(*Type_Info) T;
    return ti.type == .INTEGER || ti.type == .ENUM;
}

IsEnumType :: inline ( $T: Type ) -> bool
{
    ti := cast(*Type_Info) T;
    return ti.type == .ENUM;
}

// Get "backing type" for enums. Passthrough for the rest
GetStorageType :: inline ( $T: Type ) -> Type #compile_time
{
    if IsEnumType( T )
    {
        tie := cast(*Type_Info_Enum) T;
        return get_type( tie.internal_type );
    }
    return T;
}

CheckSpecifiedEnumType :: ( $T: Type ) #compile_time
{
    ti := cast(*Type_Info) T;
    if ti.type == .ENUM
    {
        tie := cast(*Type_Info_Enum) T;
        if tie.enum_type_flags & .SPECIFIED == 0
        {
            // #location(T) is awesome sauce!
            compiler_report( "Serialized enum type is not marked as #specified", #location(T) );
        }
    }
}

IsFloatType :: inline ( $T: Type ) -> bool
{
    return (cast(*Type_Info) T).type == .FLOAT;
}

IsArrayType :: inline ( $T: Type ) -> bool
{
    ti := cast(*Type_Info) T;
    return ti.type == .ARRAY;
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

    if ti.type != .ARRAY
        return false;

    tia := cast(*Type_Info_Array) ti;
    return IsPrimitiveType( tia.element_type );
}


#scope_module

#import "String";
#import "Math";

#load "basic.jai";
#load "datatypes.jai";

// NOTE All notes can be written as specified or with a 'reflector_' prefix before the given name
// NOTE Returns a temporary args array
// TODO Convert string args based on names & types array
ParseNote :: ( noteName: string, notes: [] string, argNames: [] string = .[], argTypes: [] Type = .[] ) -> noteIndex: int, args: []string
{
    assert( argNames.count == argTypes.count );

    name := noteName;
    prefixedName := tprint( "reflector_%", name );

    for notes
    {
        noteStr := it;
        found := false;

        // FIXME In the event of a note name collision, we just wont be able to use this at all?
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



ReflectorStrings :: #string STR

// TODO TODO TODO Ideally we'd like this to be here, so that custom user reflectors don't need to define their own version of this
// for their specific Reflector. However this currently clashes with the specialized Reflect overloads for BinaryReflector f.e.
// since overload resolution doesnt seem to consider either the 'using' relationship between BinaryReflector and Reflector,
// nor the fact that one is more "concrete" than the other (has less polymorphic args).
// See if reporting about this convinces Jon to fix it..
#if 0
{
    Reflect :: ( d: *$T, r: *Reflector ) -> ReflectResult
    #modify
    {
        ti := cast(*Type_Info) T;
        return ti.type == .STRUCT;
    }
    {
        // TODO Do we wanna keep a chached mapping of type_info to generated string?
        // NOTE according to how_to 100 though, this #run should only be invoked once for each type we pass in $T
        #insert #run GenReflectFunction( T, type_info( T ), type_of( r ) );
    }
}

// NOTE Apparently there's a limit to macro recursion .. https://github.com/Jai-Community/Jai-Community-Library/wiki/Getting-Started#nested-macros
// As demonstrated, we can refer to the constants block of the type of a declared argument to declare a separate argument, like with
// ReflectedTypeInfo here, which is freaking awesome!
ReflectField :: ( field: Code, fieldId: u16, name: string, offsetBytes: s64, info: *r.ReflectedTypeInfo, r: *$R ) #expand
{
    result: ReflectResult = .Ok;

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

