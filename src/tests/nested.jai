
SimpleType :: struct
{
    num: s32;
}

ComplexType :: struct
{
    simple: SimpleType;
    nums: [] s32;
    str: string;
}

DeepType :: struct
{
    complex: ComplexType;
    n: s32;
}

DeeperType :: struct
{
    deep: DeepType;
    someText: string;
}

ChunkyType :: struct
{
    deeper: [..] DeeperType;
}


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

    // TODO DeepEquals
    // Expect( readChunk == writtenChunk );
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

