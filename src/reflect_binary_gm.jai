#load "reflect.jai";
#load "basic.jai";
#load "datatypes.jai";

//
// Binary reflector in the style of Glowmade
// All type headers, field ids & sizes are inline (no deduplication whatsoever)
//

BinaryReflectorGM :: struct( $IsReading2: bool )
{
    #as using reflector: Reflector( BinaryTypeInfo, IsReading2, true );

    scopeDepth: s64;
}

BinaryReaderGM :: struct
{
    #as using binary: BinaryReflectorGM( true );

    buffer: [] u8;
    bufferHead: s64;
}

BinaryWriterGM :: struct
{
    #as using binary: BinaryReflectorGM( false );

    buffer: BufferBuilder( 1 * Megabytes );
}

#scope_file

// Always ensure we're not trying to read past the end of the buffer
// If you call this with an exhausted buffer, no copy will occur
Read :: inline ( using r: *BinaryReaderGM, d: *$T )
{
    bytesToCopy := min( size_of(T), buffer.count - r.bufferHead );
    Copy( buffer.data + r.bufferHead, d, bytesToCopy );
}

Read :: inline ( using r: *BinaryReaderGM, d: *$T, offset: s64 )
{
    bytesToCopy := min( size_of(T), buffer.count - offset );
    Copy( buffer.data + offset, d, bytesToCopy );
}

ReadAndAdvance :: inline ( using r: *BinaryReaderGM, d: *$T )
{
    bytesToCopy := min( size_of(T), buffer.count - bufferHead );
    Copy( buffer.data + bufferHead, d, bytesToCopy );
    bufferHead += bytesToCopy;
}

ReadAndAdvance :: inline ( using r: *BinaryReaderGM, d: [] u8 )
{
    bytesToCopy := min( d.count, buffer.count - bufferHead );
    Copy( buffer.data + bufferHead, d.data, bytesToCopy );
    bufferHead += bytesToCopy;
}


BinaryTypeInfo :: struct
{
    type:                    Type;
    startOffset:             s64;
    totalSize:               s64;       // Packed into 64 bits together with fieldCount (so 48 bits max)
    currentFieldName:        string;
    currentFieldStartOffset: s64;
    currentFieldSize:        s64;       // Packed into 64 bits together with field id (so 48 bits max)
    fieldCount:              u16;

    HeaderSize :: size_of(u64);
    TotalSizeBits :: (HeaderSize - size_of(type_of(fieldCount))) * 8;
    TotalSizeMax :: (1 << TotalSizeBits) - 1;
}

#scope_export

BeginReflectType :: ( info: *BinaryTypeInfo, type: Type, r: *BinaryReflectorGM ) -> bool
{
    #if r.IsReading
    {
        info.startOffset = r.bufferHead;

        ReadAndAdvance( r, *info.totalSize );
        info.fieldCount = cast(u16)(info.totalSize >> info.TotalSizeBits);
        info.totalSize &= info.TotalSizeMax;

        // Sanity check the total serialized size of the root type against the size of the read buffer
        // TODO Add a final verification pass and a checksum on write + Serialise/Deserialise wrappers that deal with them for when we're
        // feeling paranoid (or need to deal with over-the-wire stuff etc).
        if r.scopeDepth == 0
        {
            if info.totalSize <= info.HeaderSize || info.startOffset + info.totalSize > r.buffer.count
            {
                log_error( "Root serialized type has an invalid size: % (read buffer size is %)", info.totalSize, r.buffer.count );
                SetError( .BadData, r );
                return false;
            }
        }
    }
    else
    {
        info.type = type;
        info.startOffset = r.buffer.size;

        // Make space to write a header at the very end
        PushEmpty( *r.buffer, info.HeaderSize );
    }

    r.scopeDepth += 1;
    return true;
}

EndReflectType :: ( info: *BinaryTypeInfo, r: *BinaryReflectorGM )
{
    r.scopeDepth -= 1;

    #if r.IsReading
    {
        r.bufferHead = info.startOffset + info.totalSize;
    }
    else
    {
        // Finish packed header and write it
        info.totalSize = r.buffer.size - info.startOffset;
        if info.totalSize > info.TotalSizeMax
        {
            log_error( "Serialized size of type % does not fit in % bits!", info.type, info.TotalSizeBits );
            SetError( .Overflow, r );
            return;
        }

        header: u64 = ((cast(u64) info.fieldCount) << info.TotalSizeBits) | (cast(u64) info.totalSize);
        CopyFrom( *r.buffer, bytes_of( *header ), info.startOffset );
    }
}

BinaryFieldSize :: size_of(u64);

BeginReflectField :: ( fieldId: u16, name: string, offsetFromParent: s64, info: *BinaryTypeInfo, r: *BinaryReflectorGM ) -> bool
{
    #if r.IsReading
    {
        // If we're past the current bounds for the type, this field is missing (not an error)
        typeEndOffset := info.startOffset + info.totalSize;
        if( r.bufferHead >= typeEndOffset )
            return false;

        info.currentFieldStartOffset = r.bufferHead;

        Read( r, *info.currentFieldSize );

        decodedFieldId := cast(u16)(info.currentFieldSize >> info.TotalSizeBits);
        info.currentFieldSize &= info.TotalSizeMax;

        if decodedFieldId == fieldId
        {
            // We're good to go
        }
        else
        {
            curOffset := r.bufferHead + info.currentFieldSize;

            // Iterate over all fields in this type looking for the one we want
            found := false;
            for 0 .. info.fieldCount - 1
            {
                // If we're right at the end of the type, then we've validly read the last field, so start over from the first one
                if( curOffset >= typeEndOffset )
                    curOffset = info.startOffset + info.HeaderSize;

                decodedFieldSize: s64;
                Read( r, *decodedFieldSize, curOffset );

                decodedFieldId = cast(u16)(decodedFieldSize >> info.TotalSizeBits);
                if decodedFieldId == fieldId
                {
                    r.bufferHead = curOffset;
                    found = true;
                    break;
                }

                decodedFieldSize &= info.TotalSizeMax;

                // Move to next field
                curOffset += decodedFieldSize;
            }
            if( !found )
            {
                // This field is missing, so skip past it
                return false;
            }
        }

        r.bufferHead += BinaryFieldSize;
        return true;
    }
    else
    {
        // This should have been guaranteed during compile time
        assert( info.fieldCount < U16_MAX );

        info.fieldCount += 1;
        info.currentFieldName = name;
        info.currentFieldStartOffset = r.buffer.size;
        // Field headers are packed similar to type headers
        // TODO This is really wasteful. Replace with a separate offsets table per type (check flatbuffers format?)
        // Push a 0 placeholder for the field size (will be computed in EndReflectField)
        header: u64 = (cast(u64) fieldId) << info.TotalSizeBits;
        Push( *r.buffer, bytes_of( *header ) );
    }

    return true;
}

EndReflectField :: ( fieldId: u16, info: *BinaryTypeInfo, r: *BinaryReflectorGM )
{
    #if r.IsReading
    {
        // Set the read head to ensure it's correct
        r.bufferHead = info.currentFieldStartOffset + info.currentFieldSize;
    }
    else
    {
        // Write serialised field size at the correct placeholder offset
        fieldSize := r.buffer.size - info.currentFieldStartOffset;
        if fieldSize > info.TotalSizeMax
        {
            log_error( "Serialized field '%' does not fit in % bits!", info.currentFieldName, info.TotalSizeBits );
            SetError( .Overflow, r );
            return;
        }

        sizeDatum := bytes_of( *fieldSize );
        // Ensure we don't overwrite the existing fieldId
        sizeDatum.count = info.TotalSizeBits / 8;
        CopyFrom( *r.buffer, sizeDatum, info.currentFieldStartOffset );
    }
}

ReflectRawBytes :: inline ( d: [] u8, r: *BinaryReflectorGM )
{
    #if r.IsReading
    {
        ReadAndAdvance( r, d );
    }
    else
    {
        Push( *r.buffer, d );
    }
}

IsPrimitiveType :: inline ( ti: *Type_Info ) -> bool
{
    // TODO We probably want to be able to do something more sophisticated for enums
    return ti.type == .INTEGER || ti.type == .FLOAT || ti.type == .BOOL || ti.type == .ENUM;
}
IsPrimitiveType :: inline ( $T: Type ) -> bool
{
    return IsPrimitiveType( cast(*Type_Info) T );
}

// TODO We should be able to make these 'constexpr/eval' functions, but how does one do that in Jai?
// May be a good Q for the next Q&A
IsArrayType :: inline ( $T: Type ) -> bool
{
    ti := cast(*Type_Info) T;
    return ti.type == .ARRAY || ti.type == .STRING;
}

IsFixedArrayType :: inline ( $T: Type ) -> bool
{
    ti := cast(*Type_Info) T;
    if ti.type != .ARRAY
        return false;
    tia := cast(*Type_Info_Array) T;
    return tia.array_type == .FIXED;
}

IsPrimitiveArrayType :: inline ( $T : Type ) -> bool
{
    ti := cast(*Type_Info) T;

    if ti.type == .STRING
        return true;

    if ti.type != .ARRAY
        return false;

    tia := cast(*Type_Info_Array) ti;
    return IsPrimitiveType( tia.element_type );
}

Reflect :: inline ( d: *$T, r: *BinaryReflectorGM ) -> ReflectResult
#modify
{
    ti := cast(*Type_Info) T;
    return ti.type != .STRUCT;
}
{
    #if #run IsPrimitiveType( T )
    {
        // Just read/write the raw bytes
        ReflectRawBytes( bytes_of( d ), r );
    }
    else #if T == string
    {
        Reflect( *d.count, r );

        #if r.IsReading
        {
            // TODO Why is this triggering?
            //assert( d.data == null );
            // TODO We probably want to be much more explicit with our allocators..
            <<d = alloc_string( d.count );
        }

        ReflectRawBytes( cast([]u8)<<d, r );
    }
    else #if #run IsArrayType( T )
    {
        count := d.count;
        Reflect( *count, r );

        #if r.IsReading
        {
            #if #run IsFixedArrayType( T )
            {
                tia := cast(*Type_Info_Array) T;
                // TODO Do we want to be more fault tolerant here?
                if count != tia.array_count
                    return .BadData;
            }
            else
            {
                // TODO We probably want to be much more explicit with our allocators..
                Reset( d, count, false );
            }
        }

        #if #run IsPrimitiveArrayType( T )
        {
            tia := cast(*Type_Info_Array) T;
            bytes: []u8 = .{ d.count * tia.element_type.runtime_size, xx d.data };

            // Just read/write the raw bytes of the array elements
            ReflectRawBytes( bytes, r );
        }
        else
        {
            // TODO Test this is actually doing what we want for reading AND writing
            for * <<d
                Reflect( it, r );
        }
    }
    else
    {
        // TODO 
        #assert( false && "Not implemented" );
    }
    return .Ok;
}

ReflectPacked :: inline ( d: *$T/interface struct {}, r: *BinaryReflectorGM ) -> ReflectResult
{
    ReflectRawBytes( bytes_of( d ), r );
    return .Ok;
}


