
Color :: enum u8
{
    Red :: 0;
    Green;
    Blue :: 2;
}

Equipment :: union
{
    weapon: Weapon;
}

Vec3 :: struct @reflect_packed
{
    x, y, z: float;
}

operator == :: ( a: Vec3, b: Vec3 ) -> bool
{
    return a.x == b.x && a.y == b.y && a.z == b.z;
}

Monster :: struct
{
    pos: Vec3;                  @reflect_field(1)
    mana: s16 = 150;            @reflect_field(2)
    hp: s16 = 100;              @field(3)
    name: string = "Bob";       @field(4)
    friendly: bool = false;     @field(5)
    inventory: [..] u8;         @field(6)
    color: Color = .Blue;       @field(7)
    weapons: [..] Weapon;       @field(8)
    // TODO Implement unions properly
    //equipped: Equipment;        @field(9)
    path: [..] Vec3;            @field(10)
}

Equal :: ( a: [] $T, b: [] T ) -> bool
{
    if a.count != b.count
        return false;

    for i: 0 .. a.count - 1
        if a[i] != b[i]
            return false;

    return true;
}

Equal :: ( a: [..] $T, b: [..] T ) -> bool
{
    if a.count != b.count
        return false;

    for i: 0 .. a.count - 1
        if a[i] != b[i]
            return false;

    return true;
}

operator == :: ( a: Monster, b: Monster ) -> bool
{
    if a.pos != b.pos
    {
        print( "###NOTE a.pos = %, b.pos = %\n", a.pos, b.pos );
        return false;
    }
    if a.mana != b.mana
    {
        print( "###NOTE a.mana = %, b.mana = %\n", a.mana, b.mana );
        return false;
    }
    if a.hp != b.hp
    {
        print( "###NOTE a.hp = %, b.hp = %\n", a.hp, b.hp );
        return false;
    }
    if a.name != b.name
    {
        print( "###NOTE a.name = %, b.name = %\n", a.name, b.name );
        return false;
    }
    if a.friendly != b.friendly
    {
        print( "###NOTE a.friendly = %, b.friendly = %\n", a.friendly, b.friendly );
        return false;
    }
    if !Equal( a.inventory, b.inventory )
    {
        print( "###NOTE a.inventory = %, b.inventory = %\n", a.inventory, b.inventory );
        return false;
    }
    if a.color != b.color
    {
        print( "###NOTE a.color = %, b.color = %\n", a.color, b.color );
        return false;
    }
    if !Equal( a.weapons, b.weapons )
    {
        print( "###NOTE a.weapons = %, b.weapons = %\n", a.weapons, b.weapons );
        return false;
    }
    //if a.equipped != b.equipped
    //{
        //print( "###NOTE a.equipped = %, b.equipped = %\n", a.equipped, b.equipped );
        //return false;
    //}
    if !Equal( a.path, b.path )
    {
        print( "###NOTE a.path = %, b.path = %\n", a.path, b.path );
        return false;
    }
    return true;
}

Weapon :: struct
{
    name: string;
    damage: s16;
}

operator == :: ( a: Weapon, b: Weapon ) -> bool
{
    return a.name == b.name && a.damage == b.damage;
}
