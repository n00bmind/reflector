#import "Basic";

#load "reflect.jai";
#load "tests/monster.jai";

main :: ()
{
    m: Monster;

    writer: BinaryWriter;
    result := Reflect( *m, *writer );
    print( "Writer result: %\n", result );
    print( "Wrote % bytes\n", writer.buffer.size );

    reader: BinaryReader; // = .{ .buffer = ToTempArray( *writer.buffer ) };
    result  = Reflect( *m, *reader );
    print( "Reader result: %\n", result );
}

