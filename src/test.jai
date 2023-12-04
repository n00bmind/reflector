#import "Basic";

#load "reflect.jai";
#load "tests/monster.jai";

main :: ()
{
    r: BinaryReader;
    m: Monster;

    result := Reflect( *m, *r );
    print( "Result: %.", result );
}
