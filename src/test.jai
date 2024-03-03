#import "Basic";
#import "Windows";

// TODO Make building tests a separate build command that fetches dependencies etc.
#import "bricks";

#load "reflect_binary_gm.jai";
#load "tests/monster.jai";

main :: ()
{
    mA, mB: Monster;
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



    print( "\n\n___________\n" );
    // FIXME compiler_get_nodes() errors if the type is not visible from reflect.jai
    //Vecf :: struct
    //{
        //x, y, z: float;
    //}
    //posf: Vecf;
    //print( "Reflect() for type % is: %\n", type_of(posf),
           //type_to_string( type_info(type_of( #procedure_of_call Reflect( *posf, *writer ) )) ) );

    TestBinaryReader();
}

// FIXME compiler_get_nodes() errors if the type is not visible from reflect.jai
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

TestBinaryReader :: ()
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
        array_reserve( *reader2.typeInfoStack, 1024 );

        BeginTime( *tester );
        Reflect( *readChunk, *reader2 );
        EndTime( *tester );
        CountBytes( *tester, reader2.buffer.count );
    }
}
