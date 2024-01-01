
Kilobytes :: 1024;
Megabytes :: 1024 * Kilobytes;
Gigabytes :: 1024 * Megabytes;


offset_of :: ( $T: Type, memberName: string ) -> s64
{
    for type_info(T).members {
        if it.name == memberName return it.offset_in_bytes;
    }

    assert( false, "Type '%' does not have member '%'", T, memberName );
    return -1;
}

IsPowerOf2 :: inline ( value: $T ) -> bool
{
    return value > 0 && (value & (value - 1)) == 0;
}

