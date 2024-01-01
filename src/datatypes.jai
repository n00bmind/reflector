
BufferBuilder :: struct( PageSize: int )
{
    Page :: [] u8;

    totalSize: s64;
    pageBuffer: [] Page;
    // TODO Allocator

    #assert( IsPowerOf2( PageSize ) );
}

PushEmpty :: ( using buffer: *BufferBuilder, size: int )
{
    ResizeExtra( buffer, size );
}

ResizeExtra :: ( using buffer: *BufferBuilder, size: int )
{
    Resize( buffer, buffer.totalSize + size );
}

Resize :: ( using buffer: *BufferBuilder, size: int )
{
    // Never shrink
    if size <= totalSize
        return;

    totalSize += size;

    // Check if we need an extra page
    requiredPageCount := (totalSize + buffer.PageSize - 1) / buffer.PageSize;
    if requiredPageCount > pageBuffer.count
        GrowPageBuffer( buffer, requiredPageCount );
}

#scope_file

GrowPageBuffer :: ( using buffer: *BufferBuilder, pageCount: int )
{
    // Never shrink
    if pageCount <= pageBuffer.count
        return;

    // TODO Update compiler for new signature
    newBuffer, _ := NewArray( pageCount, buffer.Page, initialized = false );

    for it, i: pageBuffer
        newBuffer[i] = pageBuffer[i];

    for i: pageBuffer.count .. pageCount-1
        newBuffer[i], _ = NewArray( buffer.PageSize, u8, initialized = false );

    pageBuffer = newBuffer;
}

