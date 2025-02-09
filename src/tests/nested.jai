#load "nested_type.jai";

TestBinaryNestedType :: ( name: string, $Reader: Type, $Writer: Type )
{
    deeper: DeeperType =
    .{
        .{
            .{ .{ 42 }, .[ 1, 2, 3 ], "Hello Sailor" },
            666,
        },
        "Apartense vacas, que la vida es corta",
    };
    writtenChunk: ChunkyType;
    for 0..1000
        array_add( *writtenChunk.deeper, deeper );

    writer: Writer;
    result := Reflect( *writtenChunk, *writer );
    // TODO log_debug?
    // log( "Writer result: %\n", result );
    // Assume it's either a plain array or a BufferBuilder
    // #if type_info( type_of( writer.buffer ) ).type == .ARRAY
    //     log( "Wrote % bytes\n", writer.buffer.count );
    // else
    //     log( "Wrote % bytes\n", writer.buffer.count );

    readChunk: ChunkyType;
    reader: Reader;
    #if type_info( type_of( writer.buffer ) ).type == .ARRAY
        reader.buffer = writer.buffer;
    else
        reader.buffer = ToArray( *writer.buffer );
    // log( "Reading % bytes\n", reader.buffer.count );
    result = Reflect( *readChunk, *reader );
    // log( "Reader result: %\n", result );

    Expect( DeepEquals( readChunk, writtenChunk ) );
}

TestNestedTypeGM :: ()
{
    TestBinaryNestedType( "Glowmade", BinaryReaderGM, BinaryWriterGM );
} @test
TestNestedTypeFB :: ()
{
    TestBinaryNestedType( "Flatbuffers", BinaryReaderFB, BinaryWriterFB );
} @test
TestNestedTypeCustom :: ()
{
    TestBinaryNestedType( "Custom", BinaryReader, BinaryWriter );
} @test

