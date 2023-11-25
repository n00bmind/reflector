
Color :: enum u8
{
    Red :: 0;
    Green;
    Blue :: 2;
}

Equipment :: struct
{
    // TODO 
    //#place weapon: Weapon;
}

Vec3 :: struct
{
    x, y, z: float;
}

Monster :: struct @serialized
{
    pos: Vec3;                  @0
    mana: s16 = 150;            @1
    hp: s16 = 100;              @2
    name: string;               @3
    //friendly: bool = false;     @4
    inventory: [..] u8;
    color: Color = .Blue;       @5
    weapons: [..] Weapon;       @6
    equipped: Equipment;        @id(7)
    path: [..] Vec3;            @id(8)
}

Weapon :: struct
{
    name: string;
    damage: s16;
}

test :: ()
{
    testMonster: Monster;

    //BinaryWriter w;
    //Reflect( *w, *testMonster );
}
