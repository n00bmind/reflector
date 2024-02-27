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

    equal := mA == mB;
    print( "Reflected type is %\n", ifx equal "EQUAL" else "NOT EQUAL" );



    print( "\n\n___________\n" );
    pos: Vec3;
    print( "Reflect() for type % is: %\n", type_of(pos),
           type_to_string( type_info(type_of( #procedure_of_call Reflect( *pos, *writer ) )) ) );
    // FIXME compiler_get_nodes() if the type is not visible from reflect.jai (or something!?)
    //Vecf :: struct
    //{
        //x, y, z: float;
    //}
    //posf: Vecf;
    //print( "Reflect() for type % is: %\n", type_of(posf),
           //type_to_string( type_info(type_of( #procedure_of_call Reflect( *posf, *writer ) )) ) );

}

