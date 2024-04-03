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
    fields: *voffset;
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
    bufferHead: s64;
    bufferOffset: s64;
}

#scope_file

Rewind :: ( offset: s64, r: *BinaryWriterFB ) -> uoffset
{
    assert( offset <= r.bufferHead, "Buffer underflow" );
    r.bufferHead -= offset;
    r.bufferOffset = 0;

    return cast(uoffset) r.bufferHead;
}

Write :: ( data: *void, size: s64, r: *BinaryWriterFB )
{
    memcpy( *r.buffer[ r.bufferHead + r.bufferOffset ], data, size );
    r.bufferOffset += size;
}

// Rewind head back to make space then write
RewindAndWrite :: ( data: *void, size: s64, r: *BinaryWriterFB ) -> uoffset
{
    result := Rewind( size, r );
    Write( data, size, r );
    return result;
}

// Always ensure we're not trying to read past the end of the buffer
// If you call this with an exhausted buffer, no copy will occur
Read :: inline ( using r: *BinaryReaderFB, d: *$T )
{
    bytesToCopy := min( size_of(T), buffer.count - bufferHead );
    Copy( buffer.data + bufferHead, d, bytesToCopy );
}

Read :: inline ( using r: *BinaryReaderFB, offset: s64, d: *$T )
{
    bytesToCopy := min( size_of(T), buffer.count - offset );
    Copy( buffer.data + offset, d, bytesToCopy );
}

ReadAndAdvance :: inline ( using r: *BinaryReaderFB, d: *$T )
{
    bytesToCopy := min( size_of(T), buffer.count - bufferHead );
    Copy( buffer.data + bufferHead, d, bytesToCopy );
    bufferHead += bytesToCopy;
}

Read :: inline ( using r: *BinaryReaderFB, d: [] u8 )
{
    bytesToCopy := min( d.count, buffer.count - bufferHead );
    Copy( buffer.data + bufferHead, d.data, bytesToCopy );
}

Read :: inline ( using r: *BinaryReaderFB, offset: s64, d: [] u8 )
{
    bytesToCopy := min( d.count, buffer.count - offset );
    Copy( buffer.data + offset, d.data, bytesToCopy );
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
    // Relative to start of its table, unused in vectors
    offset: voffset;
}

TableInfo :: struct
{
    // Position in the buffer where these were written
    tablePos, vtablePos: uoffset;
    firstFieldIdx: s32;
    fieldCount: s32;
    maxId: u16;
    tableSize, vtableSize: s32;
}

VectorInfo :: struct
{
    // Position in the buffer
    pos: uoffset;
    size: s32;
    firstFieldIdx: s32;
    count: s32;
    data: *void;
}

StringInfo :: struct
{
    // Position in the buffer
    pos: uoffset;
    size: s32;
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
    Vector;
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
            return .Vector;

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
    rootField: FieldInfo;
    // Header is 4 bytes at a minimum
    r.measuredBufferSize = size_of(uoffset);

    result := Register( d, *rootField, r );
    if result != .Ok
        return result;

    print( "##### Measured buffer size: %\n", r.measuredBufferSize );
    r.buffer = NewArray( r.measuredBufferSize, u8 );
    r.bufferHead = r.buffer.count;

    result = Reflect( d, rootField, r );

    // Write header pointing to root table
    rootTable := *r.tables[ rootField.tableIndex ];
    p := Rewind( size_of(uoffset), r );
    assert( p == 0, "Should have filled the buffer by now" );
    Write( *rootTable.tablePos, size_of(uoffset), r );

    return result;
}
Reflect :: ( d: *$T/interface struct {}, r: *BinaryReaderFB ) -> ReflectResult
{
    rootTableOffset: uoffset;
    Read( r, *rootTableOffset );

    f: FieldInfo;
    r.bufferHead = rootTableOffset;
    result := Reflect( d, f, r );

    return result;
}


// TODO We'll need to change build.jai to be able to discover these types too?
Reflect :: ( d: *$T, sourceField: FieldInfo, r: *BinaryReflectorFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Table;
}
{
    #if r.IsWriting
    {
        table := *r.tables[ sourceField.tableIndex ];

        // Map offsets by ordered field id (id 0 is unused)
        tmpOffsets := [] voffset.{ table.maxId, talloc( table.maxId * size_of(voffset) ) };
        memset( tmpOffsets.data, 0, tmpOffsets.count * size_of(voffset) );

        field: *FieldInfo;
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

                print_to_builder( *builder, "field = *r.fields[ table.firstFieldIdx + % ];\n", tableFieldIdx ); 
                print_to_builder( *builder, "result = Reflect( *d.%, <<field, r );\n", fieldInfo.name );
                print_to_builder( *builder, "if result != .Ok return result;\n" );

                print_to_builder( *builder, "tmpOffsets[ % - 1 ] = field.offset;\n", fieldInfo.id );

                tableFieldIdx += 1;
            }
            return builder_to_string( *builder );
        }

        // Write vtable
        // TODO Deduplication
        table.vtablePos = Rewind( table.vtableSize, r );
        // Implicit conversion to u16
        assert( table.vtableSize < U16_MAX, "Vtable size overflow" );
        assert( table.tableSize < U16_MAX, "Table size overflow" );
        Write( *table.vtableSize, size_of(u16), r );
        Write( *table.tableSize, size_of(u16), r );
        Write( tmpOffsets.data, tmpOffsets.count * size_of(voffset), r );

        // Write table contents
        // TODO Alignments
        table.tablePos = Rewind( table.tableSize, r );
        relOffset: soffset = cast(soffset)(table.vtablePos - table.tablePos);
        Write( *relOffset, size_of(soffset), r );

        for idx: 0 .. table.fieldCount - 1
        {
            field = *r.fields[ table.firstFieldIdx + idx ];
            fieldType := FieldTypeFor( field.type );

            if fieldType == .Inline
                Write( field.value.value_pointer, field.size, r );
            else if fieldType == .Table
            {
                pos := r.tables[ field.tableIndex ].tablePos;
                Write( *pos, size_of(uoffset), r );
            }
            else if fieldType == .Vector
            {
                pos := r.vectors[ field.vectorIndex ].pos;
                Write( *pos, size_of(uoffset), r );
            }
            else if fieldType == .String
            {
                pos := r.strings[ field.stringIndex ].pos;
                Write( *pos, size_of(uoffset), r );
            }
        }
    }
    else #if r.IsReading
    {
        st := type_info(T);
        stNode :: #insert #run StructNodeIdentFor( type_info(T), true );

        // FIXME This won't work outside compile time!
        ok, info := GatherReflectedTypeInfo( st, stNode );
        if !ok
            return .InvalidSchema;

        tablePos := r.bufferHead;

        // Find vtable
        vTableOffset: soffset;
        Read( r, *vTableOffset );

        id: u16 = 0;
        vtable: *VTable = cast(*VTable) *r.buffer[ r.bufferHead + vTableOffset ];
        while( true )
        {
            inBounds, fieldOffset := GetField( id, vtable );
            if !inBounds
                break;

            if fieldOffset
            {
                fieldInfo := FindFieldInfo( id + 1, info );
                if fieldInfo
                {
                    r.bufferHead = tablePos + fieldOffset;

                    targetType := fieldInfo.decl.type_inst.result;
                    target: [] u8 = .{ targetType.runtime_size, cast(*u8)d + fieldInfo.offset };

                    result := Reflect( targetType, target, r );
                    if result != .Ok
                        return result;
                }
            }
        }
    }

    return .Ok;
}

Reflect :: ( targetType: *Type_Info, target: [] u8, r: *BinaryReaderFB ) -> ReflectResult
{
    fieldType := FieldTypeFor( targetType );
    if fieldType ==
    {
        case .Inline;
        {
            Read( r, target );
        }
        case .String;
        {
            offset: uoffset;
            Read( r, *offset );

            count: u32;
            Read( r, r.bufferHead + offset, *count );

            targetStr := cast(*string) target.data;
            assert( targetStr.data == null );

            <<targetStr = alloc_string( count );
            Read( r, r.bufferHead + offset + 4, cast([] u8) <<targetStr );
        }
        case .Vector;
        {
            offset: uoffset;
            Read( r, *offset );

            count: u32;
            Read( r, r.bufferHead + offset, *count );

            tia := cast(*Type_Info_Array) fieldType;
            itType := tia.element_type;
            itFieldType := FieldTypeFor( itType );

            if tia.array_type == .FIXED
            {
                // TODO Do we want to be more fault tolerant here?
                if count != tia.array_count
                    return .BadData;

                d := cast(*[] u8) target.data;
                if itFieldType == .Inline
                {
                    bytes: [] u8 = .{ count * itType.runtime_size, d.data };
                    // Just read the raw bytes of the array elements
                    Read( r, r.bufferHead + offset + 4, bytes );
                }
                else
                {
                    dataStart := r.bufferHead + offset + 4;
                    for 0 .. count - 1
                    {
                        bufferPos := dataStart + it * size_of(uoffset);
                        Read( r, bufferPos, *offset );

                        r.bufferHead = bufferPos + offset;
                        dItem := [] u8.{ itType.runtime_size, d.data + it * itType.runtime_size };

                        Reflect( itType, dItem, r );
                    }
                }
            }
            else
            {
                // TODO We'd have to manually allocate these since we can't cast them to their actual type
                //Reset( d, count, false );
            }

        }
        case .Table;
        {
            //st := cast(*Type_Info_Struct) targetType;
            //// FIXME Need the static type!
            //stNode :: #insert #run StructNodeIdentFor( targetType, true );

            //ok, info := GatherReflectedTypeInfo( st, stNode );
            //if !ok
                //return .InvalidSchema;

        }
    }

    return .Ok;
}

Reflect :: ( d: *$T, sourceField: FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Vector;
}
{
    ItType :: #run ArrayElementTypeFor( type_info(T) );
    vec := *r.vectors[ sourceField.vectorIndex ];

    for * <<d
    {
        // TODO Any tables written here will each write out a copy of the same individual vtable
        // Obvious chance for deduplication here..
        result := Reflect( it, r.fields[ vec.firstFieldIdx + it_index ], r );
        if result != .Ok
            return result;
    }

    // Write array count & contents to the buffer
    vec.pos = Rewind( vec.size, r );
    Write( *vec.count, size_of(u32), r );

    ItFieldType := FieldTypeFor( type_info(ItType) );
    if ItFieldType == .Inline
        Write( vec.data, vec.count * size_of(ItType), r );
    else
    {
        for idx: 0 .. vec.count - 1
        {
            pos: uoffset;
            itField := *r.fields[ vec.firstFieldIdx + idx ];
            if ItFieldType == .String
                pos = r.strings[ itField.stringIndex ].pos;
            else if ItFieldType == .Table
                pos = r.tables[ itField.tableIndex ].tablePos;

            Write( *pos, size_of(uoffset), r );
        }
    }

    return .Ok;
}

Reflect :: ( d: *$T, sourceField: FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .String;
}
{
    str := *r.strings[ sourceField.stringIndex ];

    str.pos = Rewind( str.size, r );
    // Implicitly convert to u32
    Write( *str.data.count, size_of(u32), r );
    Write( str.data.data, str.data.count, r );
    zero: u8 = 0;
    Write( *zero, size_of(u8), r );

    return .Ok;
}

Reflect :: ( d: *$T, sourceField: FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Inline;
}
{
    // No-op. The table writes all its inline fields already
    return .Ok;
}

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
    curOffset := size_of(soffset);

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

        print_to_builder( *builder, "table.maxId = /*info.maxId*/ %;\n", info.maxId );
        // Count only the members that are actually going to be serialised
        print_to_builder( *builder, "table.fieldCount = /*info.annotatedFieldCount*/ %;\n", info.annotatedFieldCount );
        // Fields in a table are consecutive inside r.fields, in memory order
        // I think (!) in vtables we want to list the offset of each field for all consecutive field ids in order, or 0 if that id was deprecated
        print_to_builder( *builder, "PushEmpty( *r.fields, table.fieldCount );\n\n" );

        // Vtable: 2 u16 sizes + 1 voffset per used up field id (id 0 is unused)
        print_to_builder( *builder, "table.vtableSize = 2 * size_of(u16);\n" );
        print_to_builder( *builder, "table.vtableSize += table.maxId * size_of(voffset);\n" );
        // Table: soffset to vtable + <variable> per serialised field
        // FIXME Alignment etc
        print_to_builder( *builder, "table.tableSize = size_of(soffset);\n\n" );

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
            print_to_builder( *builder, "table.tableSize += field.size;\n" );
            tableFieldIdx += 1;
        }

        return builder_to_string( *builder );
    }

    r.measuredBufferSize += table.vtableSize;
    r.measuredBufferSize += table.tableSize;

    return result;
}

Register :: ( d: *$T, targetField: *FieldInfo, r: *BinaryWriterFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Vector;
}
{
    if d.count > S32_MAX
        return .Overflow;

    targetField.size = size_of(uoffset);
    targetField.vectorIndex = cast(s32) r.vectors.count;

    vec := Push( *r.vectors );
    vec.count = cast(s32) d.count;
    vec.data = d.data;

    ItType :: #run ArrayElementTypeFor( type_info(T) );
    if FieldTypeFor( type_info(ItType) ) == .Vector
        return .InvalidSchema;

    vec.firstFieldIdx = cast(s32) r.fields.count;
    PushEmpty( *r.fields, vec.count );

    vec.size = size_of(u32);
    for * <<d
    {
        itField := *r.fields[ vec.firstFieldIdx + it_index ];
        itField.type = type_info(ItType);

        result := Register( it, itField, r );
        if result != .Ok
            return result;

        vec.size += itField.size;
    }

    r.measuredBufferSize += vec.size;

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
    str.size = cast(s32)(size_of(u32) + d.count + 1);

    // Add length of string contents
    r.measuredBufferSize += str.size;
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



ReflectPacked :: inline ( d: *$T/interface struct {}, r: *BinaryReflectorFB ) -> ReflectResult
{
    //ReflectRawBytes( bytes_of( d ), r );
    return .Ok;
}

