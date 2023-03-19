
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
    pos: Vec3;
    mana: s16 = 150;
    hp: s16 = 100;
    name: string;
    //friendly: bool = false;     @deprecated
    inventory: [..] u8;
    color: Color = .Blue;
    weapons: [..] Weapon;
    equipped: Equipment;
    path: [..] Vec3;
}

Weapon :: struct
{
    name: string;
    damage: s16;
}
