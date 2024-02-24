
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

Vec3 :: struct @reflect_packed
{
    x, y, z: float;
}

Monster :: struct
{
    pos: Vec3;                  @reflect_field(1)
    mana: s16 = 150;            @reflect_field(2)
    hp: s16 = 100;              @field(3)
    name: string;               @field(4)
    friendly: bool = false;     @field(5)
    inventory: [..] u8;         @field(6)
    color: Color = .Blue;       @field(7)
    weapons: [..] Weapon;       @field(8)
    //equipped: Equipment;        @id(7) @name(bla)
    //path: [..] Vec3;            @id(8)
}

Weapon :: struct
{
    name: string;
    damage: s16;
}
