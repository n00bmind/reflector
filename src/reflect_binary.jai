
BinaryReflector :: struct( $IsReading2: bool )
{
    #as using reflector: Reflector( BinaryTypeInfo, IsReading2, true );

    scopeDepth: s64;
}

BinaryReader :: struct
{
    #as using binary: BinaryReflector( true );

    buffer: [] u8;
    bufferHead: s64;
}

BinaryWriter :: struct
{
    #as using binary: BinaryReflector( false );

    buffer: BufferBuilder( 1 * Megabytes );
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

ReflectPacked :: inline ( d: *$T/interface struct {}, r: *BinaryReflector ) -> ReflectResult
{
    ReflectRawBytes( bytes_of( d ), r );
    return .Ok;
}


#scope_module

REFLECT_STUBS_BIN :: #string STR

Reflect :: ( d: *$T, r: *BinaryReflector ) -> ReflectResult
#modify
{
    ti := cast(*Type_Info) T;
    return ti.type == .STRUCT;
}
{
    #if r.IsWriting
    {
        if r.scopeDepth == 0
            // Leave a gap for the CRC blob offset
            PushEmpty( *r.buffer, 4 );

        result := ReflectResult.Ok;
        #insert -> string
        {
            builder: String_Builder;  
            defer free_buffers(*builder);

            _, info := GatherReflectedTypeInfo( type_info(T) );
            if info.isPacked
            {
                print_to_builder( *builder, "return inline ReflectPacked( d, r );\n" );
            }
            else
            {
                fc := info.annotatedFieldCount;
                print_to_builder( *builder, "tableStartPos := r.buffer.size;\n" );
                print_to_builder( *builder, "Push( *r.buffer, cast(u16) % );\n", fc );
                print_to_builder( *builder, "Push( *r.buffer, cast(u16) % );\n", info.maxId );
                print_to_builder( *builder, "offsetTable := []u32.{ %1, talloc( %1 * size_of(u32) ) };\n", fc );

                for fieldInfo : info.fieldInfo
                {
                    if !fieldInfo.id
                        continue;
                    print_to_builder( *builder, "Push( *r.buffer, cast(u16) % );\n", fieldInfo.id );
                }
                print_to_builder( *builder, "offsetTablePos := r.buffer.size;\n" );
                print_to_builder( *builder, "PushEmpty( *r.buffer, % );\n", 4 * fc );

                i := 0;
                for fieldInfo : info.fieldInfo
                {
                    if !fieldInfo.id
                        continue;

                    print_to_builder( *builder, "offsetTable[%] = cast(u32) r.buffer.size;\n", i );
                    print_to_builder( *builder, "result = Reflect( *d.%, r );\n", fieldInfo.name );
                    print_to_builder( *builder, "if result != .Ok return result;\n" );
                    i += 1;
                }
                print_to_builder( *builder, "CopyFrom( *r.buffer, []u8.{ offsetTable.count * size_of(u32), cast(*u8)offsetTable.data }, offsetTablePos );\n" );
            }

            return builder_to_string( *builder );
        }
    }

    #if r.IsReading
    {

    }

    return .Ok;
}

Reflect :: inline ( d: *$T, r: *BinaryReflector ) -> ReflectResult #expand
#modify
{
    ti := cast(*Type_Info) T;
    return ti.type != .STRUCT;
}
{
    #if r.IsWriting
    {

    }
    else
    {

    }

    return .Ok;
}

STR


#scope_file

BinaryTypeInfo :: struct
{

}
