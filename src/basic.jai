
offset_of :: ( $T: Type, memberName: string ) -> s64
{
    for type_info(T).members {
        if it.name == memberName return it.offset_in_bytes;
    }

    assert( false, "Type '%' does not have member '%'", T, memberName );
    return -1;
}

