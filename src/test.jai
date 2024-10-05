// TODO Add an example test case similar to what codeape does, which touches on a lot of the use cases:
// - Serialises in the metaprogram
// - Deserialises in the target program
// - Uses a custom Reflect() overload

#import "Basic";
#import "Windows";

// TODO We're inserting code that now requires the user to import stuff.. how do we deal with this?
#import "Bucket_Array";
// TODO Automate dependency downloading etc
#import "bricks";
#import "reflector";

#load "tests/monster.jai";

main :: ()
{
    TestBinarySerializerGM();
    BenchBinaryReaderGM();

    print( "\n\n___________\n\n" );

    TestBinarySerializerFB();
    BenchBinaryReaderFB();
}

// FIXME compiler_get_nodes() errors if the type is not visible from reflect.jai
// TODO This should be fixed now?
#scope_export

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

TestBinarySerializerGM :: ()
{
    print( "___Binary:\n" );

    mA, mB: Monster;
    mA.pos = .{ 1.0, 2.0, 3.0 };
    array_add( *mA.inventory, 10 );
    array_add( *mA.inventory, 20 );
    array_add( *mA.inventory, 30 );
    array_add( *mA.weapons, .{ "Hammer", 42 } );

    writer: BinaryWriterGM;
    result := Reflect( *mA, *writer );
    print( "Writer result: %\n", result );
    print( "Wrote % bytes\n", writer.buffer.size );

    reader: BinaryReaderGM = .{ buffer = ToArray( *writer.buffer ) };
    print( "Reading % bytes\n", reader.buffer.count );
    result = Reflect( *mB, *reader );
    print( "Reader result: %\n", result );

    equal := mA == mB;
    print( "Reflected type is %\n", ifx equal "EQUAL" else "NOT EQUAL" );
}

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

TestBinarySerializerFB :: ()
{
    print( "___Flatbuffers:\n" );

    mA, mB: Monster;
    mA.pos = .{ 1.0, 2.0, 3.0 };
    mA.mana = 42;
    mA.name = "Harry";
    array_add( *mA.inventory, 10 );
    array_add( *mA.inventory, 20 );
    array_add( *mA.inventory, 30 );
    array_add( *mA.weapons, .{ "Hammer", 42 } );

    writer: BinaryWriterFB;
    result := Reflect( *mA, *writer );
    print( "Writer result: %\n", result );
    print( "Wrote % bytes\n", writer.buffer.count );

    reader: BinaryReaderFB = .{ buffer = writer.buffer };
    print( "Reading % bytes\n", reader.buffer.count );
    result = Reflect( *mB, *reader );
    print( "Reader result: %\n", result );

    equal := mA == mB;
    print( "Reflected type is %\n", ifx equal "EQUAL" else "NOT EQUAL" );
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
