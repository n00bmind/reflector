
Color :: enum u8 #specified
{
    Red   :: 0;
    Green :: 1;
    Blue  :: 2;
}

Equipment :: union
{
    weapon: Weapon;
}

Vec3 :: struct @reflect_packed
{
    x, y, z: float;
}

Monster :: struct
{
    pos: Vec3;                  @reflect_field(1)
    mana: s16 = 150;            @reflect_field(2)
    hp: s16 = 100;              //@field(3)
    friendly: bool = false;     @field(5)
    name: string = "Bob";       @field(4)
    inventory: [..] u8;         @field(6)
    color: Color = .Blue;       @field(7)
    weapons: [..] Weapon;       @field(8)
    // TODO Implement unions properly
    //equipped: Equipment;        @field(9)
    path: [..] Vec3;            @field(11)
}

Weapon :: struct
{
    name: string;
    damage: s16;
}


//// Eclectic (https://github.com/dvidelabs/flatcc/blob/master/doc/eclectic.fbs)

Fruit :: enum u8
{
    Banana :: 255;
    Orange :: 42;
}

FooBar :: struct
{
    meal: Fruit = .Banana;
    //density: s64;         // Deprecated
    say: string;
    height: s16;
}



TestBinaryMonster :: ( name: string, $Reader: Type, $Writer: Type )
{
    mA, mB: Monster;
    mA.pos = .{ 1.0, 2.0, 3.0 };
    array_add( *mA.inventory, 10 );
    array_add( *mA.inventory, 20 );
    array_add( *mA.inventory, 30 );
    array_add( *mA.weapons, .{ "Hammer", 42 } );

    writer: Writer;
    writeResult := Reflect( *mA, *writer );
    // Assume it's either a plain array or a BufferBuilder
    #if type_info( type_of( writer.buffer ) ).type == .ARRAY
        log( "Wrote % bytes\n", writer.buffer.count );
    else
        log( "Wrote % bytes\n", writer.buffer.count );

    log( "Writer result: %\n", writeResult );
    Expect( writeResult == .Ok );

    reader: Reader;
    #if type_info( type_of( writer.buffer ) ).type == .ARRAY
        reader.buffer = writer.buffer;
    else
        reader.buffer = ToArray( *writer.buffer );
    log( "Reading % bytes\n", reader.buffer.count );
    readResult := Reflect( *mB, *reader );

    log( "Reader result: %\n", readResult );
    Expect( readResult == .Ok );

    Expect( DeepEquals( mA, mB ) );
}

TestMonsterGM :: ()
{
    TestBinaryMonster( "Glowmade", BinaryReaderGM, BinaryWriterGM );
} @test
TestMonsterFB :: ()
{
    TestBinaryMonster( "Flatbuffers", BinaryReaderFB, BinaryWriterFB );
} @test
TestMonster :: ()
{
    TestBinaryMonster( "Custom", BinaryReader, BinaryWriter );
} @test


TestJsonMonster :: ()
{
    mA, mB: Monster;
    mA.pos = .{ -1.0, 2.0, 3.0 };
    array_add( *mA.inventory, 1 );
    array_add( *mA.inventory, 3 );
    array_add( *mA.inventory, 7 );
    array_add( *mA.inventory, 15 );
    array_add( *mA.inventory, 31 );
    array_add( *mA.inventory, 63 );
    array_add( *mA.inventory, 127 );
    array_add( *mA.inventory, 255 );
    array_add( *mA.weapons, .{ "Sword", 69 } );

    // FIXME Enums
    // TODO Ensure all reflectors check for #specified
    writer: JsonWriter;
    writeResult := Reflect( *mA, *writer );
    log( "Writer result:\n %\n", writer.output );
} @test
