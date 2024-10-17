#import "Bucket_Array";

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

bytes_of :: inline ( v: *$T ) -> [] u8
{
    result: [] u8;
    result.data = cast(*u8) v;
    result.count = size_of(T);
    return result;
}


Copy :: inline ( source: *void, target: *void, count: s64 )
{
    memcpy( target, source, count );
}
Compare :: inline ( a: *void, b: *void, count: s64 ) -> s16
{
    return memcmp( a, b, count );
}
Set :: inline ( target: *void, value: u8, count: s64 )
{
    memset( target, value, count );
}


GetMemberValue :: inline ( m: *Type_Info_Struct_Member, d: *void ) -> Any
{
    p := cast(*u8)d + m.offset_in_bytes;
    return Any.{ m.type, p };
}
GetMemberValueAs :: inline ( m: *Type_Info_Struct_Member, d: *void, $M: Type ) -> *M
{
    p := cast(*u8)d + m.offset_in_bytes;
    return cast(*M)p;
}


///// Arrays
// TODO Allocators
Init :: inline ( a: *[] $T, count: s64, $initialized := true )
{
    array, _ = NewArray( count, T, initialized );
    <<a = array;
}

Init :: inline ( a: *[..] $T, capacity: s64 )
{
    array_reserve( a, capacity );
}

Reset :: inline ( a: *[] $T, count: s64, $initialized := true )
{
    // NOTE I dont see this doing any copies, so presumably it's assumed that realloc does that if required?
    array_resize( a, count, initialized );
}

Reset :: inline ( a: *[..] $T, count: s64, $initialized := true )
{
    // NOTE I dont see this doing any copies, so presumably it's assumed that realloc does that if required?
    array_resize( a, count, initialized );
}

Contains :: ( array: [] $T, value: T ) -> bool
{
    for array
    {
        if it == value
            return true;
    }
    return false;
}

Last :: inline ( array: [..] $T ) -> *T
{
    return ifx array.count > 0 then *array[array.count - 1] else null;
}

Push :: inline ( array: *[..] $T ) -> *T
{
    return array_add( array );
}

Push :: inline ( array: *[..] $T, item: T )
{
    array_add( array, item );
}

Push :: inline ( array: *Bucket_Array( $T, $N ) ) -> *T
{
    pointer, locator := find_and_occupy_empty_slot( array, initialize=true );
    return pointer;
}

PushEmpty :: inline ( array: *[..] $T, count: s64 )
{
    array_resize( array, array.count + count );
}

PushEmpty :: inline ( array: *Bucket_Array, count: s64 )
{
    for 1..count
        find_and_occupy_empty_slot( array, initialize=true );
}

Pop :: inline ( array: *[..] $T, out: *T )
{
    <<out = (<<array)[array.count - 1];
    array.count -= 1;
}

///// Math

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


///// Misc
ReportWarning :: ( loc: Source_Code_Location, fmt: string, args: .. Any )
{
    finalFmt := tprint( "[Reflector] Warning: %:\n > %", loc, fmt );
    log( finalFmt, ..args, loc = loc, flags = .WARNING );
} @PrintLike

// TODO How do we stop compilation when using this though?
ReportError :: ( loc: Source_Code_Location, fmt: string, args: .. Any )
{
    finalFmt := tprint( "[Reflector] ERROR: %:\n > %", loc, fmt );
    log( finalFmt, ..args, loc = loc, flags = .ERROR );
} @PrintLike

