
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

Monster :: struct @reflect
{
    //pos: Vec3;                  @0
    mana: s16 = 150;            @id
    //hp: s16 = 100;              @2
    //name: string;               @3
    ////friendly: bool = false;     @4
    //inventory: [..] u8;
    //color: Color = .Blue;       @5
    //weapons: [..] Weapon;       @6
    //equipped: Equipment;        @id(7) @name(bla)
    //path: [..] Vec3;            @id(8)
}

Weapon :: struct
{
    name: string;
    damage: s16;
}
