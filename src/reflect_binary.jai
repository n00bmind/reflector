
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


#scope_module
// TODO Stringify and insert
Reflect :: ( d: *$T/interface struct {}, r: *BinaryReflector ) -> ReflectResult
{
    #if r.IsWriting
    {
        if r.scopeDepth == 0
            // Leave a gap for the CRC blob offset
            Advance( 4, r );

        result := ReflectResult.Ok;
        #insert -> string
        {
            builder: String_Builder;  
            defer free_buffers(*builder);

            info := GatherReflectedTypeInfo( type_info(T) );
            if info.isPacked
            {
                print_to_builder( *builder, "return inline ReflectPacked( d, r );\n" );
            }
            else
            {
                fc := info.annotatedFieldCount;
                print_to_builder( *builder, "offsetTable := []u32.{ %1, talloc( %1 * size_of(u32) ) };\n", fc );
                print_to_builder( *builder, "tableStartPos := r.buffer.size;\n" );
                print_to_builder( *builder, "Write( cast(u16) %, r );\n", fc );
                print_to_builder( *builder, "Write( cast(u16) %, r );\n", info.maxId );

                for fieldInfo : info.fieldInfo
                {
                    if !fieldInfo.id
                        continue;
                    print_to_builder( *builder, "Write( cast(u16) %, r );\n", fieldInfo.id );
                }
                print_to_builder( *builder, "offsetTablePos := r.buffer.size;\n" );
                print_to_builder( *builder, "Advance( %, r );\n", 4 * fc );

                i := 0;
                for fieldInfo : info.fieldInfo
                {
                    if !fieldInfo.id
                        continue;

                    print_to_builder( *builder, "offsetTable[%] = r.buffer.size;\n", i );
                    print_to_builder( *builder, "result = Reflect( *d.%, r );\n", fieldInfo.name );
                    print_to_builder( *builder, "if result != .Ok return result;\n" );
                    i += 1;
                }
                print_to_builder( *builder, "WriteAt( offsetTablePos, offsetTable.data, offsetTable.count * size_of(u32), r );\n" );
            }

            return builder_to_string( *builder );
        }
    }

    #if r.IsReading
    {

    }
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
}



#scope_file

BinaryTypeInfo :: struct
{

}
