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

    buffer: BufferBuilder( 1 * Megabytes );
    fields: [..] FieldInfo;
    tables: [..] TableInfo;
    vectors: [..] VectorInfo;
    strings: [..] StringInfo;
}


#scope_file

FieldInfo :: struct
{
    type: *Type_Info;
    offset: voffset;        // Relative to start of its table, 0 = not present
    union
    {
        value: Any;
        tableIndex: s64;
        vectorIndex: s64;
        stringIndex: s64;
    }
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



#scope_export

// NOTE We cannot use a combined function accepting BinaryReflectorFB here, as that is still a polymorph,
// and hence atm the compiler fails to resolve that against the generic Reflect() (accepting $Reflector)
// However in this case I dont think that's all that important
Reflect :: ( d: *$T/interface struct {}, r: *BinaryWriterFB ) -> ReflectResult
{
    //#if info.IsPacked
        //return inline ReflectPacked( d, r );
    //else
    {
        dummyField: FieldInfo;
        result := Register( d, *dummyField, r );
        if result != .Ok
            return result;

        // TODO 
        // - At this point we should have everything perfectly described in the Writer
        // - Compute the total size of the buffer based on that
        // - Think how to write it "backwards"

        return result;
    }
    return .Ok;
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

// TODO We'll need to change build.jai to be able to discover these types too?
Register :: ( d: *$T, targetField: *FieldInfo, r: *BinaryReflectorFB ) -> ReflectResult
#modify
{
    // Pretty amazing to be able to do this tbh..
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Table;
}
{
    //st := type_info(T);

    //info, foundInfo := table_find( *globalStructTypeInfoTable, st );
    //assert( foundInfo, "Couldn't find compile-time ReflectedTypeInfo for type %", st.name );

    targetField.tableIndex = r.tables.count;
    table := Push( *r.tables );

    // First field in a table is the offset to its vtable
    curOffset: voffset = size_of(voffset);

    table.firstFieldIdx = cast(s32) r.fields.count;
    // TODO We need a convention for what we're gonna put in our vtables. Review how field ids are used in the "spec"
    // I think (!) in vtables we want to list the offset of each field for all consecutive field ids in order, or 0 if that id was deprecated
    PushEmpty( *r.fields, table.fieldCount );

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

        tableFieldIdx := 0;
        for m, index: st.members
        {
            fieldInfo := *info.fieldInfo[index];
            if !fieldInfo.id
                continue;

            print_to_builder( *builder, "field = *r.fields[ table.firstFieldIdx + % ];\n", tableFieldIdx );
            print_to_builder( *builder, "field.type   = cast(*Type_Info) type_of( d.% );\n", fieldInfo.name );
            print_to_builder( *builder, "field.offset = %;\n", m.offset_in_bytes );
            print_to_builder( *builder, "result = Register( *d.%, field, r );\n", fieldInfo.name );
            print_to_builder( *builder, "if result != .Ok return result;\n" );
            tableFieldIdx += 1;
        }
        // Count only the members that are actually going to be serialised
        print_to_builder( *builder, "table.fieldCount = %;\n", tableFieldIdx );

        return builder_to_string( *builder );
    }

    return result;
}

Register :: ( d: *$T, targetField: *FieldInfo, r: *BinaryReflectorFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Array;
}
{
    if d.count > S32_MAX
        return .Overflow;

    targetField.vectorIndex = cast(s32) r.vectors.count;
    vector := Push( *r.vectors );
    vector.count = cast(s32) d.count;
    vector.data = d;

    return .Ok;
}

Register :: ( d: *$T, targetField: *FieldInfo, r: *BinaryReflectorFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .String;
}
{
    targetField.stringIndex = cast(s32) r.strings.count;
    str := Push( *r.strings );
    str.data = <<d;

    return .Ok;
}

Register :: ( d: *$T, targetField: *FieldInfo, r: *BinaryReflectorFB ) -> ReflectResult
#modify
{
    fieldType := FieldTypeFor( cast(*Type_Info)T );
    return fieldType == .Inline;
}
{
    targetField.value = <<d;
    return .Ok;
}

Register :: ( d: *$T, targetField: *FieldInfo, r: *BinaryReflectorFB ) -> ReflectResult
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



//_____________________________________________

#if 0
{
    PushField :: ( f: Any, fields: *[..] FieldInfo, atIndex: s64 )
    {
        f := *fields[atIndex];
        //f.type = ...
    }

    Reflect :: ( d: *Monster, r: *BinaryWriterFB ) -> ReflectResult
    {
        table := Push( *r.tables );
        tableEntryIndex := table - r.tables.data;

        fieldCount: s32 = 0;
        // First field in a table is the offset to its vtable
        curOffset: voffset = size_of(voffset);

        table.fieldCount = 8;
        //table.maxId = 11; // ?

        table.firstFieldIdx = cast(s32) r.fields.count;
        PushEmpty( *r.fields, table.fieldCount );
        
        i := table.firstFieldIdx;
        PushField( d.pos,       *r.fields, i ); i += 1;
        PushField( d.mana,      *r.fields, i ); i += 1;
        PushField( d.hp,        *r.fields, i ); i += 1;
        PushField( d.friendly,  *r.fields, i ); i += 1;
        PushField( d.name,      *r.fields, i ); i += 1;
        PushField( d.inventory, *r.fields, i ); i += 1;
        PushField( d.color,     *r.fields, i ); i += 1;
        PushField( d.weapons,   *r.fields, i ); i += 1;
        PushField( d.path,      *r.fields, i ); i += 1;

        return .Ok;
    }
}

