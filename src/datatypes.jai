
BufferBuilder :: struct( PageSize: int )
{
    #assert( IsPowerOf2( PageSize ) );

    PageShift :: #run Log2( PageSize );
    Page :: [] u8;

    size: s64;
    pages: [] Page;
    // TODO Allocator
}

FindPage :: inline ( using buffer: *BufferBuilder, index: int ) -> pageIndex: int, offsetInPage: int
{
    pageIndex    := index >> buffer.PageShift;
    offsetInPage := index & (buffer.PageSize - 1);

    return pageIndex, offsetInPage;
}

PushEmpty :: ( using buffer: *BufferBuilder, extraSize: int )
{
    ResizeExtra( buffer, extraSize );
}

// Copy bytes from a source array and put them at a specific offset from the start of the given buffer
// The resulting target bytes may straddle a page boundary, depending on the value of atOffset and the size of the source
// If there aren't enough pages to hold the entire contents of the source array, the target buffer will be resized accordingly
// If the given offset is bigger than the current size of the target buffer, the contents of the resulting "gap bytes" are unspecified.
CopyFrom :: ( using buffer: *BufferBuilder, source: [] u8, atOffset: int )
{
    assert( atOffset >= 0 );

    if atOffset + source.count > buffer.size
        Resize( buffer, atOffset + source.count );

    pageIndex, offsetInPage := FindPage( buffer, atOffset );

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

ResizeExtra :: ( using buffer: *BufferBuilder, extraSize: int )
{
    Resize( buffer, buffer.size + extraSize );
}

Resize :: ( using buffer: *BufferBuilder, newSize: int )
{
    Reserve( buffer, newSize );
    buffer.size = newSize;
}

ReserveExtra :: ( using buffer: *BufferBuilder, extraSize: int )
{
    Reserve( buffer, buffer.size + extraSize );
}

Reserve :: ( using buffer: *BufferBuilder, newCapacity: int )
{
    requiredPageCount := (newCapacity + buffer.PageSize - 1) / buffer.PageSize;
    GrowPageBuffer( buffer, requiredPageCount );
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

