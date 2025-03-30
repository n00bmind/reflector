// TODO Add a new "NaiveReflector" contender using the reflection module included with the compiler (i.e. "runtime" reflection)
#import "Basic";

#import "reflector";
#import "rep-tester";
#import "unotest";  // For DeepEquals

#load "tests/nested_type.jai";


main :: ()
{
    BenchmarkBinaryReader( "Signature", BinaryReader, BinaryWriter );
    // print( "\n\n___________\n\n" );
    // BenchmarkBinaryReader( "Glowmade", BinaryReaderGM, BinaryWriterGM );
    // print( "\n\n___________\n\n" );
    // BenchmarkBinaryReader( "Flatbuffers", BinaryReaderFB, BinaryWriterFB );
}

#scope_file

BenchmarkBinaryReader :: ( name: string, $Reader: Type, $Writer: Type )
{
    print( "___% speed:\n", name );
    deeper: DeeperType =
    .{
        .{
            .{ .{ 42 }, .[ 1, 2, 3 ], "Hello Sailor" },
            666,
        },
        "Apartense vacas, que la vida es corta",
    };

    // TODO Figure out how to get the size of L3 in the machine, and create a test that reads several times that amount
    // to ensure we're always benchmarking against the main memory bandwidth
    // TODO Write a test that finds the ballpark memory bandwidth in the machine as a baseline for comparison
    // https://www.computerenhance.com/p/cache-size-and-bandwidth-testing?r=1nj2pu&utm_campaign=post&utm_medium=web
    writtenChunk: ChunkyType;
    for 0..8000
        array_add( *writtenChunk.deeper, deeper );

    writer: Writer;
    result := Reflect( *writtenChunk, *writer );
    print( "Writer result: %\n", result );
    print( "Wrote % bytes\n", writer.buffer.count );

    readChunk: ChunkyType;
    // Assume it's either a plain array or a BufferBuilder
    #if type_info( type_of( writer.buffer ) ).type == .ARRAY
        reader: Reader = .{ buffer = writer.buffer };
    else
        reader: Reader = .{ buffer = ToArray( *writer.buffer ) };
    print( "Reading % bytes\n", reader.buffer.count );
    result = Reflect( *readChunk, *reader );
    print( "Reader result: %\n", result );

    assert( DeepEquals( readChunk, writtenChunk ) );


    tester: RepetitionTester;
    NewTestWave( *tester, reader.buffer.count );

    #if type_info( type_of( writer.buffer ) ).type == .ARRAY
        array := writer.buffer;
    else
        array := ToArray( *writer.buffer, allocator = context.allocator );

    while BeginTestCycle( *tester )
    {
        reader2: Reader = .{ buffer = array };

        BeginTime( *tester );
        Reflect( *readChunk, *reader2 );
        EndTime( *tester );
        CountBytes( *tester, reader2.buffer.count );

        reset_temporary_storage();
    }
}

