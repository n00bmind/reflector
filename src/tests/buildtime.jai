
// NOTE This method needs constant values hence cannot be used to test types containing dynamic arrays
SerializedFoo: DeeperType:
.{
    .{
        .{ .{ 42 }, .[ 3, 2, 1 ], "Cowabunga" },
        999,
    },
    "Hermano, permanece fiel a la tierra",
};

#placeholder BuildTimeBuffer;       // [] u8


TestBuildtimeSerializer:: ()
{
    foo := SerializedFoo;

    writer: BinaryWriterGM;
    writeResult := Reflect( *foo, *writer );
    // Assume it's either a plain array or a BufferBuilder
    log( "Writer result: % (wrote % bytes)\n", writeResult, writer.buffer.count );

    Expect( writeResult == .Ok );

    // Create a byte array literal to insert back into the program
    builder: String_Builder;
    append( *builder, "BuildTimeBuffer :: u8.[\n" );

    output := ToArray( *writer.buffer );
    for output
    {
        row := it_index / 16;
        col := it_index % 16;

        if col == 0
            print_to_builder( *builder, "    " );

        print_to_builder( *builder, "0x%,\t", formatInt(output[it_index], base=16) );

        if col == 15
            print_to_builder( *builder, "\n" );
    }

    append( *builder, "];\n" );
    // Add to the current workspace
    add_build_string( builder_to_string( *builder ), w = -1 );

} @test_buildtime

TestBuildtimeDeserializer:: ()
{
    reader: BinaryReaderGM;
    reader.buffer = BuildTimeBuffer;
    log( "Reading % bytes\n", reader.buffer.count );

    readThing: DeeperType;
    readResult := Reflect( *readThing, *reader );

    log( "Reader result: %\n", readResult );
    Expect( readResult == .Ok );

    Expect( DeepEquals( readThing, SerializedFoo ) );

} @test_buildtime @test
