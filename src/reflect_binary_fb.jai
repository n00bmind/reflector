
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
    fields: [0] voffset;    // Any number of fields starting at this offset, 2 bytes per entry, according to 'size'
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
    #as using reflector: Reflector( FBTypeInfo, IsReading2, true );
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
    tables: [..] FBTableInfo;
}


#scope_file

FBTableInfo :: struct
{
    // This is what gets dumped to the vtable: a list of offsets to the source table, sorted by field id, starting at 0
    fieldOffsets: [..] voffset;
}

FBTypeInfo :: struct
{
    // (write-only?) Entry in the list of tables
    tableEntryIndex: int;
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

#scope_export

BeginReflectType :: ( info: *FBTypeInfo, type: Type, r: *BinaryReflectorFB ) -> bool
{
    #if r.IsWriting
    {
        // Introspect type to find out the size of the table for this type
        tableSize := ComputeTableSize( type );

        // TODO Then push that whole amount to the buffer straight away to create the "high watermark" where a nested type would have to jump to
        
        // Get a slot in the global list of tables so that all parents appear in that list before their children
        tableInfo: *FBTableInfo = Push( r.tables );
        info.tableEntryIndex = tableInfo - r.tables.data;

        array_reserve( *tableInfo.fieldOffsets, 8 );
    }
    return true;
}

BeginReflectField :: ( fieldId: u16, name: string, offsetFromParent: s64, info: *FBTypeInfo, r: *BinaryReflectorFB ) -> bool
{
    #if r.IsWriting
    {
        tableInfo: *FBTableInfo = *r.tables[ info.tableEntryIndex ];

        // Our field ids start at 1 (TODO do we actually need that), but FB starts at 0
        EnsureSize( *tableInfo.fieldOffsets, fieldId );
        tableInfo.fieldOffsets[ fieldId - 1 ] = offsetFromParent;
    }
    return true;
}

EndReflectField :: ( fieldId: u16, info: *FBTypeInfo, r: *BinaryReflectorFB )
{

}

EndReflectType :: ( info: *FBTypeInfo, r: *BinaryReflectorFB )
{

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

ReflectPacked :: inline ( d: *$T/interface struct {}, r: *BinaryReflectorFB ) -> ReflectResult
{
    //ReflectRawBytes( bytes_of( d ), r );
    return .Ok;
}

