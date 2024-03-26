// TODO This generates redeclaration errors.. so how is one supposed to resolve transitive dependencies?
//#load "reflect.jai";

//
// Binary reflector for the Flatbuffers format
// Not trying to be perfectly conforming to spec, yet.
//

// Stored always aligned to their own size
ScalarType :: enum
{
    fb_bool;
    fb_uint8;
    fb_uint16;
    fb_uint32;
    fb_uint64;
    fb_int8;
    fb_int16;
    fb_int32;
    fb_int64;
    fb_float32;
    fb_float64;
    fb_enum;
}

// TODO Not clear what the size of a bool actually is..
fb_false :: 0;
fb_true :: !fb_false;


uoffset :: u32;
soffset :: s32;
voffset :: u16;
identifier :: [4] u8;

// For fields pointing to sub-tables, vectors and strings
// NOTE This require that these types of objects always live *after* the table referencing them in the buffer
At :: ( p: *uoffset ) -> *u8
{
    return (cast(*u8)p) + <<p;
}

// For vtables
At :: ( p: *soffset ) -> *u8
{
    return (cast(*u8)p) - <<p;
}

// For vtable entries
At :: ( tableBase: *u8, f: voffset ) -> *u8
{
    return tableBase + f;
}


Header :: struct
{
    rootTable: uoffset;
    id: identifier;
}

// These should be hashed & deduplicated during writing
VTable :: struct
{
    size: u16;
    tableSize: u16;
    // A list of offsets to the source table, sorted by field id, starting at 0
    // Any number of fields starting at this offset, 2 bytes per entry, according to 'size'
    fields: [0] voffset;
}

GetField :: ( fieldId: int, vt: *VTable ) -> bool, voffset
{
    offsetBytes := (fieldId + 2) * size_of(voffset);
    if offsetBytes < vt.size
        return true, <<((cast(*voffset)vt) + fieldId + 2);
    else
        return false, 0;
}

//u32 flatbuffers_type_hash_from_name(const char *name)
//{
    //uint32_t hash = 2166136261UL;
    //while (*name) {
        //hash ^= (uint32_t)*name;
        //hash = hash * 16777619UL;
        //++name;
    //}
    //if (hash == 0) {
        //hash = 2166136261UL;
    //}
    //return hash;
//}



BinaryReflectorFB :: struct( $IsReading2: bool )
{
    #as using reflector: Reflector( void, IsReading2, true );
}

BinaryReaderFB :: struct
{
    #as using binary: BinaryReflectorFB( true );

    buffer: [] u8;
    bufferHead: s64;
}

BinaryWriterFB :: struct
{
    #as using binary: BinaryReflectorFB( false );

    buffer: [] u8;
    fields: [..] FieldInfo;
    tables: [..] TableInfo;
    vectors: [..] VectorInfo;
    strings: [..] StringInfo;
    measuredBufferSize: s64;
    scopeDepth: s64;
    bufferHead: s32;
}

#scope_file

Write :: ( data: *void, size: s32, r: *BinaryWriterFB ) -> s32
{
    // Pop head back to make space then write
    r.bufferHead -= size;
    memcpy( *r.buffer[ r.bufferHead ], data, size );
    return r.bufferHead;
}


FieldInfo :: struct
{
    type: *Type_Info;
    union
    {
        value: Any;
        tableIndex: s64;
        vectorIndex: s64;
        stringIndex: s64;
    }
    size: s32;
    offset: voffset;        // Relative to start of its table, 0 = not present
}

TableInfo :: struct
{
    // Position in the buffer where these were written (once we know it)
    tablePos, vtablePos: s32;
    firstFieldIdx: s32;
    fieldCount: s32;
    tableSize, vtableSize: u16;
}

VectorInfo :: struct
{
    // Position in the buffer (once we know it)
    pos: s32;
    count: s32;
    data: *void;
}

StringInfo :: struct
{
    // Position in the buffer (once we know it)
    pos: s32;
    // TODO Remember to null-terminate appropriately
    data: string;
}


// FIXME Incorporate alignment rules!
ComputeTableSize :: ( type: Type ) -> s64
{
    ti := cast(*Type_Info) type;
    assert( ti.type == .STRUCT, "We only care about structs here!" );
    tis := cast(*Type_Info_Struct) type;

    // At a minimum, 1 soffset pointing to the vtable
    totalSize := size_of(soffset);
    for m: tis.members
    {
        // NOTE TODO The computed sizes here heavily depend on what's implemented or not at the reflector level!
        // So check with that code often to ensure its in sync
        if m.type.type ==
        {
            case .INTEGER; #through;
            case .FLOAT; #through;
            case .BOOL; #through;
            case .ENUM;
                totalSize += m.type.runtime_size;
            case .STRUCT;
            case .ARRAY;
            case .STRING;
                totalSize += size_of(uoffset);
            case;
                assert( false, "Unsupported member type: %\n", m.type.type );
            // TODO 
            //case .ANY;
            //case .POINTER;

            //case .OVERLOAD_SET;
            //case .POLYMORPHIC_VARIABLE;
            //case .TYPE;
            //case .CODE;
            //case .VARIANT;
            //case .PROCEDURE;
            //case .VOID;
        }
    }
    return totalSize;
}

FieldType :: enum
{
    Ignored;
    Inline;
    Table;
    Array;
    String;
}
FieldTypeFor :: ( t: *Type_Info ) -> FieldType
{
    if t.type ==
    {
        case .INTEGER; #through;
        case .FLOAT; #through;
        case .BOOL; #through;
        case .ENUM;
            return .Inline;

        case .STRUCT;
            return .Table;

        case .ARRAY;
            return .Array;

        case .STRING;
            return .String;
    }
    return .Ignored;
}

ArrayElementTypeFor :: ( t: *Type_Info_Array ) -> Type
{
    return get_type( t.element_type );
}


#scope_export

// NOTE We cannot use a combined function accepting BinaryReflectorFB here, as that is still a polymorph,
// and hence atm the compiler fails to resolve that against the generic Reflect() (accepting $Reflector)
// However in this case I dont think that's all that important
Reflect :: ( d: *$T/interface struct {}, r: *BinaryWriterFB ) -> ReflectResult
{
    if( r.scopeDepth == 0 )
    {
        //#if info.IsPacked
        //return inline ReflectPacked( d, r );
        //else
        {
            // Header is 4 bytes at a minimum
            r.measuredBufferSize = size_of(uoffset);

            dummyField: FieldInfo;
            result := Register( d, *dummyField, r );
            if result != .Ok
                return result;

            print( "##### Measured buffer size: %\n", r.measuredBufferSize );
            r.buffer = NewArray( r.measuredBufferSize, u8 );
            r.bufferHead = cast(s32) r.buffer.count;
        }
    }

    r.scopeDepth += 1;

    dummyField: FieldInfo;
    result := Reflect( d, dummyField, r );
    return result;
}

Reflect :: ( d: *$T, field: FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Table;
}
{
    table := *r.tables[ field.tableIndex ];

    result := ReflectResult.Ok;
    #insert -> string
    {
        // Call typed Reflect on each serialised field
        st := type_info(T);
        stNode :: #insert #run StructNodeIdentFor( type_info(T), true );

        _, info := GatherReflectedTypeInfo( st, stNode );

        builder: String_Builder;  
        defer free_buffers(*builder);

        tableFieldIdx := 0;
        for m, index: st.members
        {
            fieldInfo := *info.fieldInfo[index];
            if !fieldInfo.id
                continue;

            print_to_builder( *builder, "result = Reflect( *d.%, r.fields[ table.firstFieldIdx + % ], r );\n", fieldInfo.name, tableFieldIdx );
            print_to_builder( *builder, "if result != .Ok return result;\n" );

            tableFieldIdx += 1;
        }
        return builder_to_string( *builder );
    }

    // TODO Write table & vtable


    return .Ok;
}

Reflect :: ( d: *$T, field: FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Array;
}
{
    ArrayType :: #run ArrayElementTypeFor( type_info(T) );
    vec := *r.vectors[ field.vectorIndex ];

    // Recover typed array
    array := [] ArrayType.{ vec.count, vec.data };
    for array
    {
        // FIXME We need to do this assignment of fields to each slot in the Register function
        // TODO Any tables written here will each write out a copy of the same individual vtable
        // Obvious chance for deduplication here..
        result := Reflect( *it, r.fields[ vec.firstFieldIndex + it_index ], r );
        if result != .Ok
            return result;
    }

    // TODO Write actual array to the buffer

    return .Ok;
}

Reflect :: ( d: *$T, field: FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .String;
}
{
    str := *r.strings[ field.stringIndex ];

    tmpBuffer: *u8 = talloc( str.data.count + 1 );
    memcpy( tmpBuffer, str.data.data, str.data.count );
    tmpBuffer[str.data.count] = 0;

    str.pos = Write( tmpBuffer, cast(s32) str.data.count + 1, r );
    return .Ok;
}

Reflect :: ( d: *$T, field: FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Inline;
}
{
    // No-op. The table writes all its fields already
    return .Ok;
}

// TODO We'll need to change build.jai to be able to discover these types too?
Register :: ( d: *$T, targetField: *FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    // Pretty amazing to be able to do this tbh..
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Table;
}
{
    targetField.size = size_of(uoffset);
    targetField.tableIndex = r.tables.count;
    table := Push( *r.tables );
    table.firstFieldIdx = cast(s32) r.fields.count;

    // First field in a table is the offset to its vtable
    curOffset := size_of(voffset);

    field: *FieldInfo;
    result := ReflectResult.Ok;
    // Explode all struct fields (that have an id) and call the appropriate typed Register on each
    // TODO Probably a good idea to turn this into a RegisterField() macro
    #insert -> string
    {
        st := type_info(T);
        stNode :: #insert #run StructNodeIdentFor( type_info(T), true );
        assert( stNode != null, "Code node for type '%' not available", st.name );

        ok, info := GatherReflectedTypeInfo( st, stNode );
        if !ok
            return "return .InvalidSchema;";

        builder: String_Builder;  
        defer free_buffers(*builder);

        // Count only the members that are actually going to be serialised
        print_to_builder( *builder, "table.fieldCount = /*info.annotatedFieldCount*/ %;\n", info.annotatedFieldCount );
        // Fields in a table are consecutive inside r.fields, in memory order
        // I think (!) in vtables we want to list the offset of each field for all consecutive field ids in order, or 0 if that id was deprecated
        print_to_builder( *builder, "PushEmpty( *r.fields, table.fieldCount );\n\n" );

        // Vtable: 2 u16 sizes + 1 voffset per used up field id (id 0 is unused)
        print_to_builder( *builder, "r.measuredBufferSize += 2 * size_of(u16);\n" );
        print_to_builder( *builder, "r.measuredBufferSize += /*info.maxId*/ % * size_of(voffset);\n", info.maxId );
        // Table: soffset to vtable + <variable> per serialised field
        // FIXME Alignment etc
        print_to_builder( *builder, "r.measuredBufferSize += size_of(soffset);\n\n" );

        tableFieldIdx := 0;
        for m, index: st.members
        {
            fieldInfo := *info.fieldInfo[index];
            if !fieldInfo.id
                continue;

            print_to_builder( *builder, "field = *r.fields[ table.firstFieldIdx + % ];\n", tableFieldIdx );
            print_to_builder( *builder, "field.type   = cast(*Type_Info) type_of( d.% );\n", fieldInfo.name );
            print_to_builder( *builder, "field.offset = cast(voffset) curOffset;\n" );
            print_to_builder( *builder, "result = Register( *d.%, field, r );\n", fieldInfo.name );
            print_to_builder( *builder, "if result != .Ok return result;\n" );

            print_to_builder( *builder, "curOffset += field.size;\n" );
            tableFieldIdx += 1;
        }

        return builder_to_string( *builder );
    }

    return result;
}

Register :: ( d: *$T, targetField: *FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Array;
}
{
    if d.count > S32_MAX
        return .Overflow;

    targetField.size = size_of(uoffset);
    targetField.vectorIndex = cast(s32) r.vectors.count;

    vector := Push( *r.vectors );
    vector.count = cast(s32) d.count;
    vector.data = d.data;

    // FIXME Vector of structs & tables & strings!
    r.measuredBufferSize += targetField.size;
    // Add length of array contents
    r.measuredBufferSize += size_of(u32) + vector.count * size_of(T);
    return .Ok;
}

Register :: ( d: *$T, targetField: *FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .String;
}
{
    targetField.size = size_of(uoffset);
    targetField.stringIndex = cast(s32) r.strings.count;

    str := Push( *r.strings );
    str.data = <<d;

    r.measuredBufferSize += targetField.size;
    // Add length of string contents
    r.measuredBufferSize += size_of(u32) + d.count + 1;
    return .Ok;
}

Register :: ( d: *$T, targetField: *FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Inline;
}
{
    targetField.size = size_of(T);
    targetField.value = <<d;

    r.measuredBufferSize += targetField.size;
    return .Ok;
}

Register :: ( d: *$T, targetField: *FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Ignored;
}
{
    #assert( false, "FB reflection for type % not implemented!", type_info(T).type );
}



Reflect :: ( d: *$T/interface struct {}, r: *BinaryReaderFB ) -> ReflectResult
{
    return .Ok;
}

ReflectPacked :: inline ( d: *$T/interface struct {}, r: *BinaryReflectorFB ) -> ReflectResult
{
    //ReflectRawBytes( bytes_of( d ), r );
    return .Ok;
}

