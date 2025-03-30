
OverloadedMonster :: struct
{
    mana: s16 = 150;                    @reflector_field(2)
    hp: s16 = 100;                      //@field(3)
    friendly: bool = false;             @field(5)
    name: string = "Bob";               @field(4)
    inventory: [..] u8;                 @field(6)
    weapons: [..] OverloadedWeapon;     @field(8)
}

OverloadedWeapon :: struct
{
    name: string;
    damage: s16;
}


globalCustomReflectCalled: bool;
Reflect :: ( d: *OverloadedWeapon, r: *$Reflector ) -> ReflectResult
{
    base64: string;
    // Just for lulz, reflect an encoded base64 string
    #if r.IsWriting
    {
        base64 = base64_encode( d.name );
    }
    Reflect( *base64, r );
    #if r.IsReading
    {
        d.name = base64_decode( base64 );
    }

    Reflect( *d.damage, r );

    // I was here
    globalCustomReflectCalled = true;
    return .Ok;
}

TestOverloadedMonster :: ( name: string, $Reader: Type, $Writer: Type )
{
    mA, mB: OverloadedMonster;
    mA.mana = 666;
    array_add( *mA.inventory, 10 );
    array_add( *mA.inventory, 20 );
    array_add( *mA.inventory, 30 );
    array_add( *mA.weapons, .{ "SwordAndBoard", 69 } );
    array_add( *mA.weapons, .{ "Bow", 42 } );
    array_add( *mA.weapons, .{ "Hammer", 121 } );

    globalCustomReflectCalled = false;
    writer: Writer;
    writeResult := Reflect( *mA, *writer );
    log( "Wrote % bytes\n", writer.buffer.count );

    log( "Writer result: %\n", writeResult );
    Expect( writeResult == .Ok );
    Expect( globalCustomReflectCalled );

    globalCustomReflectCalled = false;
    reader: Reader;
    #if type_info( type_of( writer.buffer ) ).type == .ARRAY
        reader.buffer = writer.buffer;
    else
        reader.buffer = ToArray( *writer.buffer );
    log( "Reading % bytes\n", reader.buffer.count );
    readResult := Reflect( *mB, *reader );

    log( "Reader result: %\n", readResult );
    Expect( readResult == .Ok );
    Expect( globalCustomReflectCalled );

    Expect( DeepEquals( mA, mB ) );
}

TestOverloadedMonsterGM :: ()
{
    TestOverloadedMonster( "Glowmade", BinaryReaderGM, BinaryWriterGM );
} @test
// NOTE FB reflector doesnt support overloading rn
// TestOverloadedMonsterFB :: ()
// {
//     TestOverloadedMonster( "Flatbuffers", BinaryReaderFB, BinaryWriterFB );
// } @test
TestOverloadedMonsterCustom :: ()
{
    TestOverloadedMonster( "Custom", BinaryReader, BinaryWriter );
} @test


#scope_file

#import "Base64";
