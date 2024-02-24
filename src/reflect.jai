#import "Compiler";
#import "Bucket_Array";
#import "Math";
#import "String";

#load "basic.jai";
#load "datatypes.jai";


// TODO Turn polymorph args into ReflectorFlags, most likely
Reflector :: struct ($IsReading: bool, $SupportsPackedTypes: bool = false)
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
    if reflector.SupportsPackedTypes
    {
        packedFound, packedArgs := ParseNote( "packed", rootDecl.notes );
        isPacked = packedFound;
    }

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
                if contains( fieldStructType.notes, "packed" )
                    info.flags |= .Packed;
            }

            // TODO Parse optional name attribute etc.

            annotatedFieldCount += 1;
        }

        // If no member fields have been identified, and this is not a 'packed' struct, default to in-memory-order consecutive automatic ids,
        // so that if the user decides in the future he wants to change the default, old data can still be read
        if annotatedFieldCount == 0
        {
            report_warning( make_location( rootDecl ),
                            "Structured type '%' will be serialised but has no serialisation notes. Will default to memory-order fields.",
                            st.name );
        }

        //append( *globalBuilder, tprint( "Reflect :: ( d: *%, r: *Reflector ) -> ReflectResult\n", st.name ) );
        //append( *globalBuilder, "{\n" );
        append( *globalBuilder, "    info: ReflectedTypeInfo;\n" );
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
                print( "+%. %: % (%)  '%'\n", m.offset_in_bytes, m.name, type_to_string( m.type ), m.type.runtime_size, m.notes );
                append( *globalBuilder, tprint( "        ReflectField( *d.%, %, \"%\", *info, r );\n", m.name, info.id, m.name ) );
            }
        }

        append( *globalBuilder, "    }\n" );
        // TODO Test that this correctly returns any errors set in EndReflectType
        append( *globalBuilder, "    return r.error;\n" );
        //append(*globalBuilder, "}\n");
    }

    return builder_to_string( *globalBuilder );
}

// Generate the body of the function based on the type it was called with
// This way we only generate the overloads that are actually needed
// This signature seems to allow creating a specific overload for structs without using #modify
// TODO When writing, *always order by offset in the source struct type* for cache friendliness
// TODO When reading, the stream tells us the order of members to write to, which probably means the function body is the same
// for all types, and we just HAVE TO do dynamic dispatch? Although, we can have a (compiletime) table of field id to member typeinfo
// and recover a typed pointer to the member doing something like:
                //M := get_root_type( m.type );
                //Reflect( GetMemberValueAs( m, d, M ), r );

// NOTE Looking at the signature & body of this procedure, it might appear that what we're saying here is that we want many different
// overloads of the same Reflect() function, all of them with the exact same signature (*all of them polymorphic on T*), but each with a
// different body, and the compiler would then have to try to match them all one by one to whatever type we're passing, in essence
// operating by 'duck typing' alone, which would be extremely inefficient and have the potential of having more than one overload end up
// with identical bodies (and collide) if we ever try to pass two structs containing the same exact members with the same exact types.
// HOWEVER that's not at all what's happening here. Instead a separate overloaded *instance* of the polymorph is being created, each
// with its own inserted body, and with a signature matching only the concrete type that's being passed.
// This can be easily demostrated with code like:
//
//    pos: Vec3;
//    print( "Reflect() for type % is: %\n", type_of(pos),
//           type_to_string( type_info(type_of( #procedure_of_call Reflect( *pos, *reflector ) )) ) );
//
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
ReflectField :: ( field: Code, fieldId: u16, name: string, info: *ReflectedTypeInfo, r: *Reflector ) #expand
{
    result: ReflectResult = .Ok;

    //fieldOffset := ReflectFieldOffset( r );      
    if BeginReflectField( fieldId, name, info, r )  // *reflectedTypeInfo, attribs ) )
    {                                                     
        result = Reflect( #insert field, r );                        

        EndReflectField( fieldId, info, r );  // fieldOffset, &info, 
    }

    if result != .Ok
    {
        SetError( result, r );
        // Return from outer Reflect() function
        `return result;
    }
}


//
// BINARY
//

BinaryReflector :: struct( $IsReading2: bool )
{
    #as using reflector: Reflector( IsReading2, true );

    scopeDepth: s64;
}

BinaryReader :: struct
{
    #as using binary: BinaryReflector( true );

    buffer: [] u8;
    bufferHead: s64;
}

// Always ensure we're not trying to read past the end of the buffer
// If you call this with an exhausted buffer, no copy will occur
Read :: inline ( using r: *BinaryReader, d: *$T )
{
    bytesToCopy := min( size_of(T), buffer.count - r.bufferHead );
    Copy( buffer.data + r.bufferHead, d, bytesToCopy );
}

Read :: inline ( using r: *BinaryReader, d: *$T, offset: s64 )
{
    bytesToCopy := min( size_of(T), buffer.count - offset );
    Copy( buffer.data + offset, d, bytesToCopy );
}

ReadAndAdvance :: inline ( using r: *BinaryReader, d: *$T )
{
    bytesToCopy := min( size_of(T), buffer.count - bufferHead );
    Copy( buffer.data + bufferHead, d, bytesToCopy );
    bufferHead += bytesToCopy;
}

ReadAndAdvance :: inline ( using r: *BinaryReader, d: [] u8 )
{
    bytesToCopy := min( d.count, buffer.count - bufferHead );
    Copy( buffer.data + bufferHead, d.data, bytesToCopy );
    bufferHead += bytesToCopy;
}

BinaryWriter :: struct
{
    #as using binary: BinaryReflector( false );

    buffer: BufferBuilder( 1 * Megabytes );
}


ReflectedTypeInfo :: struct
{
    type:                    Type;
    startOffset:             s64;
    totalSize:               s64;       // Packed into 64 bits together with fieldCount (so 48 bits max)
    currentFieldName:        string;
    currentFieldStartOffset: s64;
    currentFieldSize:        s64;       // Packed into 64 bits together with field id (so 48 bits max)
    fieldCount:              u16;

    HeaderSize :: size_of(u64);
    TotalSizeBits :: (HeaderSize - size_of(type_of(fieldCount))) * 8;
    TotalSizeMax :: (1 << TotalSizeBits) - 1;
}

// TODO Begin/End ReflectType should also probably return a bool!?
BeginReflectType :: ( info: *ReflectedTypeInfo, type: Type, r: *BinaryReflector ) -> bool
{
    #if r.IsReading
    {
        info.startOffset = r.bufferHead;

        ReadAndAdvance( r, *info.totalSize );
        info.fieldCount = cast(u16)(info.totalSize >> info.TotalSizeBits);
        info.totalSize &= info.TotalSizeMax;

        // Sanity check the total serialized size of the root type against the size of the read buffer
        // TODO Add a final verification pass and a checksum on write + Serialise/Deserialise wrappers that deal with them for when we're
        // feeling paranoid (or need to deal with over-the-wire stuff etc).
        if r.scopeDepth == 0
        {
            if info.totalSize <= info.HeaderSize || info.startOffset + info.totalSize > r.buffer.count
            {
                log_error( "Root serialized type has an invalid size: % (read buffer size is %)", info.totalSize, r.buffer.count );
                SetError( .BadData, r );
                // FIXME Really we want to abort the whole process here (so return a bool!)
                return false;
            }
        }
    }
    else
    {
        info.type = type;
        info.startOffset = r.buffer.size;

        // Make space to write a header at the very end
        PushEmpty( *r.buffer, info.HeaderSize );
    }

    r.scopeDepth += 1;
    return true;
}

EndReflectType :: ( info: *ReflectedTypeInfo, r: *BinaryReflector )
{
    r.scopeDepth -= 1;

    #if r.IsReading
    {
        r.bufferHead = info.startOffset + info.totalSize;
    }
    else
    {
        // Finish packed header and write it
        info.totalSize = r.buffer.size - info.startOffset;
        if info.totalSize > info.TotalSizeMax
        {
            log_error( "Serialized size of type % does not fit in % bits!", info.type, info.TotalSizeBits );
            SetError( .Overflow, r );
            return;
        }

        header: u64 = ((cast(u64) info.fieldCount) << info.TotalSizeBits) | (cast(u64) info.totalSize);
        CopyFrom( *r.buffer, bytes_of( *header ), info.startOffset );
    }
}

BinaryFieldSize :: size_of(u64);

BeginReflectField :: ( fieldId: u16, name: string, info: *ReflectedTypeInfo, r: *BinaryReflector ) -> bool
{
    #if r.IsReading
    {
        // If we're past the current bounds for the type, this field is missing (not an error)
        typeEndOffset := info.startOffset + info.totalSize;
        if( r.bufferHead >= typeEndOffset )
            return false;

        info.currentFieldStartOffset = r.bufferHead;

        Read( r, *info.currentFieldSize );

        decodedFieldId := cast(u16)(info.currentFieldSize >> info.TotalSizeBits);
        info.currentFieldSize &= info.TotalSizeMax;

        if decodedFieldId == fieldId
        {
            // We're good to go
        }
        else
        {
            curOffset := r.bufferHead + info.currentFieldSize;

            // Iterate over all fields in this type looking for the one we want
            found := false;
            for 0 .. info.fieldCount - 1
            {
                // If we're right at the end of the type, then we've validly read the last field, so start over from the first one
                if( curOffset >= typeEndOffset )
                    curOffset = info.startOffset + info.HeaderSize;

                decodedFieldSize: s64;
                Read( r, *decodedFieldSize, curOffset );

                decodedFieldId = cast(u16)(decodedFieldSize >> info.TotalSizeBits);
                if decodedFieldId == fieldId
                {
                    r.bufferHead = curOffset;
                    found = true;
                    break;
                }

                decodedFieldSize &= info.TotalSizeMax;

                // Move to next field
                curOffset += decodedFieldSize;
            }
            if( !found )
            {
                // This field is missing, so skip past it
                return false;
            }
        }

        r.bufferHead += BinaryFieldSize;
        return true;
    }
    else
    {
        // This should have been guaranteed during compile time
        assert( info.fieldCount < U16_MAX );

        info.fieldCount += 1;
        info.currentFieldName = name;
        info.currentFieldStartOffset = r.buffer.size;
        // Field headers are packed similar to type headers
        // TODO This is really wasteful. Replace with a separate offsets table per type (check flatbuffers format?)
        // Push a 0 placeholder for the field size (will be computed in EndReflectField)
        header: u64 = (cast(u64) fieldId) << info.TotalSizeBits;
        Push( *r.buffer, bytes_of( *header ) );
    }

    return true;
}

EndReflectField :: ( fieldId: u16, info: *ReflectedTypeInfo, r: *BinaryReflector )
{
    #if r.IsReading
    {
        // Set the read head to ensure it's correct
        r.bufferHead = info.currentFieldStartOffset + info.currentFieldSize;
    }
    else
    {
        // Write serialised field size at the correct placeholder offset
        fieldSize := r.buffer.size - info.currentFieldStartOffset;
        if fieldSize > info.TotalSizeMax
        {
            log_error( "Serialized field '%' does not fit in % bits!", info.currentFieldName, info.TotalSizeBits );
            SetError( .Overflow, r );
            return;
        }

        sizeDatum := bytes_of( *fieldSize );
        // Ensure we don't overwrite the existing fieldId
        sizeDatum.count = info.TotalSizeBits / 8;
        CopyFrom( *r.buffer, sizeDatum, info.currentFieldStartOffset );
    }
}

ReflectRawBytes :: inline ( d: [] u8, r: *BinaryReflector )
{
    #if r.IsReading
    {
        ReadAndAdvance( r, d );
    }
    else
    {
        Push( *r.buffer, d );
    }
}

IsPrimitiveType :: ( ti: *Type_Info ) -> bool
{
    // TODO We probably want to be able to do something more sophisticated for enums
    return ti.type == .INTEGER || ti.type == .FLOAT || ti.type == .BOOL || ti.type == .ENUM;
}

IsArrayType :: ( ti: *Type_Info ) -> bool
{
    return ti.type == .ARRAY || ti.type == .STRING;
}

IsPrimitiveArrayType :: ( ti: *Type_Info ) -> bool
{
    if ti.type == .STRING
        return true;

    if ti.type != .ARRAY
        return false;

    tia := cast(*Type_Info_Array) ti;
    return IsPrimitiveType( tia.element_type );
}

Reflect :: inline ( d: *$T, r: *BinaryReflector ) -> ReflectResult
#modify
{
    ti := cast(*Type_Info) T;
    return ti.type != .STRUCT;
}
{
    #if #run IsPrimitiveType( cast(*Type_Info) T )
    {
        // Just read/write the raw bytes
        ReflectRawBytes( bytes_of( d ), r );
    }
    else #if #run IsPrimitiveArrayType( cast(*Type_Info) T )
    {
        // Just read/write the raw bytes of the array elements
        tia := cast(*Type_Info_Array) T;
        bytes: []u8 = .{ d.count * tia.element_type.runtime_size, d.data };

        ReflectRawBytes( bytes, r );
    }
    else #if #run IsArrayType( cast(*Type_Info) T )
    {
        Reflect( *d.count, r );

        // TODO Test this is actually doing what we want for reading AND writing
        for * <<d
            Reflect( it, r );
    }
    else
    {
        // TODO 
        #assert( false && "Not implemented" );
    }
    return .Ok;
}

ReflectPacked :: inline ( d: *$T/interface struct {}, r: *BinaryReflector ) -> ReflectResult
{
    ReflectRawBytes( bytes_of( d ), r );
    return .Ok;
}

