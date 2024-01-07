#import "Basic";

#load "reflect.jai";
#load "tests/monster.jai";

main :: ()
{
    writer: BinaryWriter;
    reader: BinaryReader;
    m: Monster;

    result := Reflect( *m, *writer );
    print( "Writer result: %\n", result );
    print( "Wrote % bytes\n", writer.buffer.size );

    result  = Reflect( *m, *reader );
    print( "Reader result: %\n", result );
}

