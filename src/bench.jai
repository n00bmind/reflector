#import "Basic";
// TODO We're inserting code that now requires the user to import stuff.. how do we deal with this?
#import "Bucket_Array";

// TODO Automate dependency downloading etc
#import "bricks";
#import "reflector";


main :: ()
{
    BenchBinaryReaderGM();
    print( "\n\n___________\n\n" );
    BenchBinaryReaderFB();
}

#scope_file

BenchBinaryReaderGM :: ()
{
    print( "___Binary speed:\n" );
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

    writer: BinaryWriterGM;
    result := Reflect( *writtenChunk, *writer );
    print( "Writer result: %\n", result );
    print( "Wrote % bytes\n", writer.buffer.size );

    readChunk: ChunkyType;
    reader: BinaryReaderGM = .{ buffer = ToArray( *writer.buffer ) };
    print( "Reading % bytes\n", reader.buffer.count );
    result = Reflect( *readChunk, *reader );
    print( "Reader result: %\n", result );


    tester: RepetitionTester;
    NewTestWave( *tester, reader.buffer.count );

    array := ToArray( *writer.buffer );
    while BeginTestCycle( *tester )
    {
        reader2: BinaryReaderGM = .{ buffer = array };

        BeginTime( *tester );
        Reflect( *readChunk, *reader2 );
        EndTime( *tester );
        CountBytes( *tester, reader2.buffer.count );
    }
}

BenchBinaryReaderFB :: ()
{
    print( "___Flatbuffers speed:\n" );
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

    writer: BinaryWriterFB;
    result := Reflect( *writtenChunk, *writer );
    print( "Writer result: %\n", result );
    print( "Wrote % bytes\n", writer.buffer.count );

    readChunk: ChunkyType;
    reader: BinaryReaderFB = .{ buffer = writer.buffer };
    print( "Reading % bytes\n", reader.buffer.count );
    result = Reflect( *readChunk, *reader );
    print( "Reader result: %\n", result );


    tester: RepetitionTester;
    NewTestWave( *tester, reader.buffer.count );

    while BeginTestCycle( *tester )
    {
        reader2: BinaryReaderFB = .{ buffer = writer.buffer };

        BeginTime( *tester );
        Reflect( *readChunk, *reader2 );
        EndTime( *tester );
        CountBytes( *tester, reader2.buffer.count );
    }
}

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

