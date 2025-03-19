
//// BufferBuilder

BufferBuilder :: struct( PageSize: int )
{
    #assert( IsPowerOf2( PageSize ) );

    PageShift :: #run Log2( PageSize );
    Page :: [] u8;

    count: s64;
    pages: [] Page;
    // TODO Allocator
}

FindPage :: inline ( using buffer: *BufferBuilder, index: int ) -> pageIndex: int, offsetInPage: int
{
    pageIndex    := index >> buffer.PageShift;
    offsetInPage := index & (buffer.PageSize - 1);

    return pageIndex, offsetInPage;
}

Push :: ( using buffer: *BufferBuilder, source: [] u8 )
{
    CopyFrom( buffer, source, buffer.count );
}

Push :: ( using buffer: *BufferBuilder, value: $T )
{
    source := value;
    CopyFrom( buffer, []u8.{ size_of(type_of( source )), cast(*u8) *source }, buffer.count );
}

PushEmpty :: ( using buffer: *BufferBuilder, extraSize: int )
{
    ResizeExtra( buffer, extraSize );
}

// Copy bytes from a source array and put them at a specific offset from the start of the given builder
// The resulting target bytes may straddle a page boundary, depending on the value of tgtOffset and the size of the source
// If there aren't enough pages to hold the entire contents of the source array, the target builder will be resized accordingly
// If tgtOffset is bigger than the current size of the target builder, the contents of the resulting "gap bytes" are unspecified.
CopyFrom :: ( using buffer: *BufferBuilder, source: [] u8, tgtOffset: int )
{
    assert( tgtOffset >= 0 );

    if tgtOffset + source.count > buffer.count
        Resize( buffer, tgtOffset + source.count );

    pageIndex, offsetInPage := FindPage( buffer, tgtOffset );

    p := buffer.pages.data + pageIndex;
    src := source.data;
    remaining := source.count;

    while remaining > 0
    {
        bytesToCopy := min( buffer.PageSize - offsetInPage, remaining );
        Copy( src, p.data + offsetInPage, bytesToCopy );

        offsetInPage = 0;
        p += 1;
        src += bytesToCopy;
        remaining -= bytesToCopy;
    }
}

// Copy bytes to a target array, optionally starting at a specific offset from the start of the given source builder
// Only data up to the end of the builder will be copied, so if srcOffset + target.count is bigger than the current size of the
// source builder, the remaining bytes in target are left untouched.
CopyTo :: ( using buffer: *BufferBuilder, target: [] u8, srcOffset: int = 0 )
{
    assert( srcOffset >= 0 );

    pageIndex, offsetInPage := FindPage( buffer, srcOffset );

    p := buffer.pages.data + pageIndex;
    tgt := target.data;
    remaining := min( target.count, buffer.count - srcOffset );

    while remaining > 0
    {
        bytesToCopy := min( buffer.PageSize - offsetInPage, remaining );
        Copy( p.data + offsetInPage, tgt, bytesToCopy );

        offsetInPage = 0;
        p += 1;
        tgt += bytesToCopy;
        remaining -= bytesToCopy;
    }
}

// NOTE Returned array is temporary by default
ToArray :: ( using buffer: *BufferBuilder, allocator: Allocator = temp ) -> [] u8
{
    result, _ := NewArray( count, u8, false,, allocator );
    CopyTo( buffer, result );

    return result;
}

ResizeExtra :: ( using buffer: *BufferBuilder, extraSize: int )
{
    Resize( buffer, buffer.count + extraSize );
}

Resize :: ( using buffer: *BufferBuilder, newSize: int )
{
    Reserve( buffer, newSize );
    buffer.count = newSize;
}

ReserveExtra :: ( using buffer: *BufferBuilder, extraSize: int )
{
    Reserve( buffer, buffer.count + extraSize );
}

Reserve :: ( using buffer: *BufferBuilder, newCapacity: int )
{
    requiredPageCount := (newCapacity + buffer.PageSize - 1) / buffer.PageSize;
    GrowPageBuffer( buffer, requiredPageCount );
}


//// TempHeap

TempHeap :: struct
{
    PageSize :: 8 * 1024 * 1024;
    Page :: struct
    {
        base: *u8;
        used: s64;
    }

    pages: [..] Page;
}

Reset :: ( using heap: *TempHeap )
{
    for * p: pages
        p.used = 0;
    array_resize( *pages, 0 );

    Init( *pages, 8 );
    AllocPage( heap );
}

Alloc :: ( using heap: *TempHeap, size: int ) -> *void
{
    curPage := *pages[ pages.count - 1 ];
    available := TempHeap.PageSize - curPage.used;

    if available < size
        AllocPage( heap );

    curPage = *pages[ pages.count - 1 ];
    // TODO Alignment?
    result := curPage.base + curPage.used;
    curPage.used += size;

    return result;
}

#scope_file

GrowPageBuffer :: ( using buffer: *BufferBuilder, pageCount: int )
{
    // Never shrink
    if pageCount <= pages.count
        return;

    // TODO Update compiler for new signature
    newPages, _ := NewArray( pageCount, buffer.Page, initialized = false );

    for it, i: pages
        newPages[i] = pages[i];

    for i: pages.count .. pageCount-1
        newPages[i], _ = NewArray( buffer.PageSize, u8, initialized = false );

    pages = newPages;
}

AllocPage :: ( using heap: *TempHeap )
{
    prevCount := pages.count;
    array_resize( *pages, pages.count + 1 );

    curPage := *pages[ prevCount ];
    // Assume once we've called Reset() any existing page memory is now invalid
    curPage.base = talloc( TempHeap.PageSize );
    curPage.used = 0;
}
