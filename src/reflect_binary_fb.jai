
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
    #as using reflector: Reflector( StaticTypeInfo, IsReading2, true );
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

    buffer: BufferBuilder( 1 * Megabytes );
    fields: [..] FieldInfo;
    tables: [..] TableInfo;
    vector: [..] VectorInfo;
    strings: [..] StringInfo;
}


#scope_file

FieldInfo :: struct
{
    type: *Type_Info_Struct_Member;
    offset: voffset;        // Relative to start of its table, 0 = not present
    union
    {
        value: *void;
        tableIndex: s64;
        vectorIndex: s64;
        stringIndex: s64;
    }
}

TableInfo :: struct
{
    // Position in the buffer where these were written (once we know it)
    tablePos, vtablePos: s32;
    firstFieldIdx, fieldCount: s32;
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

StaticFieldInfo :: struct
{
    id: u16;
}
StaticTypeInfo :: struct
{
    fieldInfo: [] StaticFieldInfo;
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
        // NOTE TODO The computed sizes here heavily depend on what's implemented or not
        // at the generic reflector level! So check GenReflectFunction often to ensure its in sync
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

GenWriteFunction :: ( T: Type, st: *Type_Info_Struct ) -> string #expand #compile_time
{
    rootNode, _ := #insert #run GetCodeNodesFor( type_info(T).name );
    assert( rootNode.kind == .IDENT );

    rootDecl := (cast(*Code_Ident) rootNode).resolved_declaration;

    ok, info := GatherTypeInfo( T, st, rootDecl );
    if !ok
        return "";


    defer free_buffers( *globalBuilder );

    if info.isPacked
    {
        append( *globalBuilder, "    return inline ReflectPacked( d, r );\n" );
    }
    else
    {
        append( *globalBuilder, "    info: StaticTypeInfo : .{\n" );
        append( *globalBuilder, "        .[\n" );
        for m, index: st.members
        {
            fieldInfo := *info.fieldInfo[index];
            append( *globalBuilder, tprint( "            .{ % },\n", fieldInfo.id ) );
        }
        append( *globalBuilder, "        ]\n" );
        append( *globalBuilder, "    };\n" );
        append( *globalBuilder, "    return inline ReflectStruct( d, info, r );\n" );
    }

    return builder_to_string( *globalBuilder );
}

#scope_export

// NOTE We cannot use a combined function accepting BinaryReflectorFB here, as that is still a polymorph,
// and hence atm the compiler fails to resolve that against the generic Reflect() (accepting $Reflector)
// However in this case I dont think that's all that important
Reflect :: ( d: *$T/interface struct {}, r: *BinaryWriterFB ) -> ReflectResult
{
    #insert #run GenWriteFunction( T, type_info( T ) );
}

Reflect :: ( d: *$T/interface struct {}, r: *BinaryReaderFB ) -> ReflectResult
{
    return .Ok;
}

Reflect :: inline ( d: *$T, r: *BinaryReflectorFB ) -> ReflectResult
#modify
{
    ti := cast(*Type_Info) T;
    return ti.type != .STRUCT;
}
{

    return .Ok;
}

ReflectStruct :: inline ( d: *$T/interface struct {}, info: StaticTypeInfo, r: *BinaryReflectorFB ) -> ReflectResult
{
    #if r.IsWriting
    {
        table := Push( *r.tables );
        // TODO How do we communicate this index to the parent table relative to us?
        tableEntryIndex := table - r.tables.data;

        st: *Type_Info_Struct = type_info(T);
        for m, index: st.members
        {
            fieldInfo := *info.fieldInfo[index];
            print( "#### FB writing field id %\n", fieldInfo.id );
        }
    }

    return .Ok;
}

ReflectPacked :: inline ( d: *$T/interface struct {}, r: *BinaryReflectorFB ) -> ReflectResult
{
    //ReflectRawBytes( bytes_of( d ), r );
    return .Ok;
}

