#import "Basic";

#load "reflect.jai";
#load "tests/monster.jai";

main :: ()
{
    mA, mB: Monster;

    writer: BinaryWriter;
    result := Reflect( *mA, *writer );
    print( "Writer result: %\n", result );
    print( "Wrote % bytes\n", writer.buffer.size );

    reader: BinaryReader = .{ buffer = ToArray( *writer.buffer ) };
    print( "Reading % bytes\n", reader.buffer.count );
    result = Reflect( *mB, *reader );
    print( "Reader result: %\n", result );

    equal := Compare( *mA, *mB, size_of(Monster) ) == 0;
    print( "Reflected type is %\n", ifx equal "EQUAL" else "NOT EQUAL" );
}

