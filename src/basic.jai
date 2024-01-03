
Kilobytes :: 1024;
Megabytes :: 1024 * Kilobytes;
Gigabytes :: 1024 * Megabytes;


Copy :: inline ( source: *void, dest: *void, count: s64 )
{
    memcpy( dest, source, count );
}
Compare :: inline (a: *void, b: *void, count: s64) -> s16
{
    return memcmp( a, b, count );
}
Set :: inline (dest: *void, value: u8, count: s64)
{
    memset( dest, value, count );
}

offset_of :: ( $T: Type, memberName: string ) -> s64
{
    for type_info(T).members {
        if it.name == memberName return it.offset_in_bytes;
    }

    assert( false, "Type '%' does not have member '%'", T, memberName );
    return -1;
}

bytes_of :: ( v: *$T ) -> [] u8
{
    result: [] u8;
    result.data = cast(*u8) v;
    result.count = size_of(T);
    return result;
}

IsPowerOf2 :: inline ( value: $T ) -> bool
{
    return value > 0 && (value & (value - 1)) == 0;
}

Log2 :: inline ( n: s64 ) -> int
{
    assert( n > 0 );

//#if COMPILER_MSVC
    //unsigned long result;
    //_BitScanReverse64( &result, (u64)n );
//#else
    CountShift :: ( bits: int ) #expand
    {
        if( `n >> bits ) { `n >>= bits; result += bits; }
    }

    result := 0;
    CountShift(32);
    CountShift(16);
    CountShift(8);
    CountShift(4);
    CountShift(2);
    CountShift(1);
//#endif

    return result;
}
