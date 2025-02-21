
// TODO Cannot have dynamic arrays here can we
ConstantFoo: DeeperType:
.{
    .{
        .{ .{ 42 }, .[ 3, 2, 1 ], "Cowabunga" },
        999,
    },
    "Hermano, permanece fiel a la tierra",
};

#placeholder BuildTimeBuffer;       // [] u8


TestBuildTimeSerializer:: ()
{
    foo := ConstantFoo;

    writer: BinaryWriterGM;
    writeResult := Reflect( *foo, *writer );
    // Assume it's either a plain array or a BufferBuilder
    log( "Writer result: % (wrote % bytes)\n", writeResult, writer.buffer.count );

    Expect( writeResult == .Ok );


    output := ToArray( *writer.buffer );

    // Create a byte array literal to insert back into the program
    builder: String_Builder;
    append( *builder, "BuildTimeBuffer :: u8.[\n" );

    rowCount := output.count / 16;
    for r: 0 .. rowCount - 1
    {
        print_to_builder( *builder, "    " );
        for c: 0 .. 15
        {
            idx := r * 16 + c;
            if idx >= output.count
                break r;

            print_to_builder( *builder, "0x%,\t", formatInt(output[idx], base=16) );
        }
        print_to_builder( *builder, "\n" );
    }

    append( *builder, "];\n" );
    // Add to the current workspace
    add_build_string( builder_to_string( *builder ), w = -1 );

} @test_buildtime
