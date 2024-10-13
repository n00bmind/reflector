// TODO Add an example test case similar to what codeape does, which touches on a lot of the use cases:
// - Serialises in the metaprogram
// - Deserialises in the target program
// - Uses a custom Reflect() overload

#import "Basic";
// TODO We're inserting code that now requires the user to import stuff.. how do we deal with this?
#import "Bucket_Array";

// TODO Automate dependency downloading etc
#import "bricks";
#import "reflector";

#load "tests/monster.jai";

main :: ()
{
    TestBinarySerializer( "Glowmade", BinaryReaderGM, BinaryWriterGM );
    print( "___________\n\n" );
    TestBinarySerializer( "Flatbuffers", BinaryReaderFB, BinaryWriterFB );
    print( "___________\n\n" );
    TestBinarySerializer( "Signature", BinaryReader, BinaryWriter );
}

#scope_file

TestBinarySerializer :: ( name: string, $Reader: Type, $Writer: Type )
{
    print( "___%___:\n", name );

    mA, mB: Monster;
    mA.pos = .{ 1.0, 2.0, 3.0 };
    array_add( *mA.inventory, 10 );
    array_add( *mA.inventory, 20 );
    array_add( *mA.inventory, 30 );
    array_add( *mA.weapons, .{ "Hammer", 42 } );

    writer: Writer;
    result := Reflect( *mA, *writer );
    print( "Writer result: %\n", result );
    // Assume it's either a plain array or a BufferBuilder
    #if type_info( type_of( writer.buffer ) ).type == .ARRAY
        print( "Wrote % bytes\n", writer.buffer.count );
    else
        print( "Wrote % bytes\n", writer.buffer.size );

    reader: Reader;
    #if type_info( type_of( writer.buffer ) ).type == .ARRAY
        reader.buffer = writer.buffer;
    else
        reader.buffer = ToArray( *writer.buffer );
    print( "Reading % bytes\n", reader.buffer.count );
    result = Reflect( *mB, *reader );
    print( "Reader result: %\n", result );

    equal := mA == mB;
    print( "Reflected type is %\n", ifx equal "EQUAL" else "NOT EQUAL" );
}

