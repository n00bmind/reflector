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
        info.startOffset = r.buffer.count;

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
        info.totalSize = r.buffer.count - info.startOffset;
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
        info.currentFieldStartOffset = r.buffer.count;
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
        fieldSize := r.buffer.count - info.currentFieldStartOffset;
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

ReflectPacked :: inline ( d: *$T/interface struct {}, r: *BinaryReflectorGM ) -> ReflectResult
{
    ReflectRawBytes( bytes_of( d ), r );
    return .Ok;
}


#scope_module

// TODO See how could make this part of the Reflector (struct) interface,
// so that the plugin knows what to insert for each Reflector subtype
BinaryReflectorGMStrings :: #string STR

// TODO Declaring this should be redundant once we are allowed to define a "root" Reflect() for type Reflector
// NOTE This overload also needs to be inserted, because it calls into the "root" ReflectField, which is also inserted
Reflect :: ( d: *$T, r: *BinaryReflectorGM ) -> ReflectResult
#modify
{
    ti := cast(*Type_Info) T;
    return ti.type == .STRUCT;
}
{
    // TODO Do we wanna keep a cached mapping of type_info to generated string?
    // (for the 'production-ready' generators we need this anyway to generate the type descriptor tables)
    // Note that according to how_to 100 though, this #run should only be invoked once for each type we pass in $T
    // Do we see two because we pass both a reader and a writer in r for each type?
    #insert #run GenReflectFunction( T, type_info( T ), type_of( r ) );
}

Reflect :: inline ( d: *$T, r: *BinaryReflectorGM ) -> ReflectResult #expand
#modify
{
    ti := cast(*Type_Info) T;
    return ti.type != .STRUCT;
}
// TODO This body should belong in a function called ReflectPrimitive, and we should be calling into that automatically
// from reflect.jai from a Reflect() overload with a #modify block like the one just above
// TODO I suppose the same issue with ambiguity that we have with the struct Reflect applies here..
{
    #if #run IsPrimitiveType( T )
    {
        #run CheckSpecifiedEnumType( T );

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
                assert( d.count == count );
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
        // TODO Do we wanna have some default implementation for pointers?
        #assert false "Not implemented. You must provide your own Reflect() overload for this type.";
    }
    return .Ok;
}

STR

