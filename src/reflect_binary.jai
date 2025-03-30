
BinaryReflector :: struct( $IsReading2: bool )
{
    #as using reflector: Reflector( BinaryTypeInfo, IsReading2, true );

    // TODO Use this in all other reflectors for comparison, as well as for writing
    heap: TempHeap;
    scopeDepth: s64;
}

BinaryReader :: struct
{
    #as using binary: BinaryReflector( true );

    buffer: [] u8;
    bufferHead: s64;
}

BinaryWriter :: struct
{
    #as using binary: BinaryReflector( false );

    buffer: BufferBuilder( 1 * Megabytes );
}


ReflectRawBytes :: inline ( d: [] u8, r: *BinaryReflector )
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

ReflectPacked :: inline ( d: *$T/interface struct {}, r: *BinaryReflector ) -> ReflectResult
{
    ReflectRawBytes( bytes_of( d ), r );
    return .Ok;
}


#scope_module

BinaryReflectorStrings :: #string STR

Reflect :: ( d: *$T, r: *BinaryReflector ) -> ReflectResult
#modify
{
    ti := cast(*Type_Info) T;
    return ti.type == .STRUCT;
}
{
    #if r.IsWriting
    {
        if r.scopeDepth == 0
            // Leave a gap for the CRC blob offset
            PushEmpty( *r.buffer, 4 );

        r.scopeDepth += 1;

        result := ReflectResult.Ok;
        #insert -> string
        {
            builder: String_Builder;  
            builder.allocator = temp;

            _, info := GatherReflectedTypeInfo( type_info(T) );
            if info.isPacked
            {
                print_to_builder( *builder, "return inline ReflectPacked( d, r );\n" );
            }
            else
            {
                fc := info.annotatedFieldCount;
                print_to_builder( *builder, "tableStartPos := r.buffer.count;\n" );
                print_to_builder( *builder, "Push( *r.buffer, cast(u16) % );\n", fc );
                print_to_builder( *builder, "Push( *r.buffer, cast(u16) % );\n", info.maxId );
                print_to_builder( *builder, "offsetTable := []u32.{ %1, talloc( %1 * size_of(u32) ) };\n", fc );

                for fieldInfo : info.fieldInfo
                {
                    if !fieldInfo.id
                        continue;
                    print_to_builder( *builder, "Push( *r.buffer, cast(u16) % );\n", fieldInfo.id );
                }
                print_to_builder( *builder, "offsetTablePos := r.buffer.count;\n" );
                print_to_builder( *builder, "PushEmpty( *r.buffer, % );\n", 4 * fc );

                i := 0;
                for fieldInfo : info.fieldInfo
                {
                    if !fieldInfo.id
                        continue;

                    print_to_builder( *builder, "offsetTable[%] = cast(u32) (r.buffer.count - tableStartPos);\n", i );
                    print_to_builder( *builder, "result = Reflect( *d.%, r );\n", fieldInfo.name );
                    print_to_builder( *builder, "if result != .Ok return result;\n" );
                    i += 1;
                }
                print_to_builder( *builder, "CopyFrom( *r.buffer, []u8.{ offsetTable.count * size_of(u32), cast(*u8)offsetTable.data }, offsetTablePos );\n" );
            }

            return builder_to_string( *builder );
        }

        r.scopeDepth -= 1;
    }

    #if r.IsReading
    {
        crcOffset: u32;
        if r.scopeDepth == 0
        {
            Reset( *r.heap );
            // Leave a gap for the CRC blob offset
            ReadAndAdvance( r, *crcOffset );
        }

        r.scopeDepth += 1;

        _, info :: #run GatherReflectedTypeInfo( type_info(T) );
        // NOTE For whatever reason, reading struct members is not constant, even if the struct is..
        #if #run info.isPacked
        {
            return inline ReflectPacked( d, r );
        }
        else
        {
            tableStartPos := r.bufferHead;

            fieldCount, maxFieldId: u16;
            ReadAndAdvance( r, *fieldCount );
            ReadAndAdvance( r, *maxFieldId );

            // TODO Allocate temp memory in big chunks and just grab from there
            idTable := []u16.{ fieldCount, Alloc( *r.heap, fieldCount * size_of(u16) ) };
            // Read whole table in one go
            ReadAndAdvance( r, idTable );

            // Reconstruct contiguous offsets table, indexed by the field ids above
            offsetTable := []u32.{ maxFieldId + 1, Alloc( *r.heap, (maxFieldId + 1) * size_of(u32) ) };
            for id : idTable
            {
                ReadAndAdvance( r, *offsetTable[id] );
            }

            result := ReflectResult.Ok;
            #insert -> string
            {
                builder: String_Builder;  
                builder.allocator = temp;

                _, info := GatherReflectedTypeInfo( type_info(T) );
                for fieldInfo : info.fieldInfo
                {
                    if !fieldInfo.id
                        continue;

                    // TODO Think about how we could avoid this branch
                    // (experiment with using id slot 0 to point past the end of the buffer, so that any subsequent reads are no-ops?)
                    print_to_builder( *builder, "if % <= maxFieldId {\n", fieldInfo.id );
                    print_to_builder( *builder, "    SetBufferHead( r, tableStartPos + offsetTable[ % ]);\n", fieldInfo.id );
                    print_to_builder( *builder, "    Reflect( *d.%, r );\n", fieldInfo.name );
                    print_to_builder( *builder, "}\n" );
                }

                return builder_to_string( *builder );
            }
        }

        r.scopeDepth -= 1;
    }

    return .Ok;
}

// TODO Add flags that govern whether strings, arrays and pointers to data are:
// - Serialised in-line or out
// - Allocated in place when reading or point to the loaded buffer's contents
Reflect :: inline ( d: *$T, r: *BinaryReflector ) -> ReflectResult
#modify
{
    ti := cast(*Type_Info) T;
    return ti.type != .STRUCT;
}
{
    #if #run IsPrimitiveType( T )
    {
        #run CheckSpecifiedEnumType( T );

        // Just read/write the raw bytes
        ReflectRawBytes( bytes_of( d ), r );
    }
    else #if T == string
    {
        // TODO Ensure all counts we serialise are compatible with whatever offset limits we end up with (u32 most likely)
        // TODO Encode null-termination somehow so it is preserved across a reflection roundtrip?
        Reflect( *d.count, r );

        #if r.IsWriting
            ReflectRawBytes( cast([]u8)<<d, r );
        else
        {
            d.data = r.buffer.data + r.bufferHead;
            Advance( r, d.count );
        }
    }
    else #if #run IsArrayType( T )
    {
        // TODO Ensure all counts we serialise are compatible with whatever offset limits we end up with (u32 most likely)
        count := d.count;
        Reflect( *count, r );

        tia := cast(*Type_Info_Array) T;
        #if r.IsReading
        {
            // TODO Presumably if this was allocated on the stack, it's still the same as any other array "view"?
            #if #run IsFixedArrayType( T )
            {
                // FIXME During reading we're not gonna be checking return types and instead should accum errors somewhere?
                // TODO Do we want to be more fault tolerant here?
                if count != tia.array_count
                    return .BadData;
            }
            else
            {
                // TODO We probably want to be much more explicit with our allocators..
                // TODO For "out-of-band" stuff like non-fixed arrays, we probably wanna have a queue where we put stuff to
                // fill out at the very end, after we're done loading all the "in-line" content
                Reset( d, count, initialized = false );
            }
        }

        #if #run IsPrimitiveArrayType( T )
        {
            #if r.IsWriting
            {
                bytes: []u8 = .{ d.count * tia.element_type.runtime_size, xx d.data };
                // Just read/write the raw bytes of the array elements
                ReflectRawBytes( bytes, r );
            }
            else
            {
                d.count = count;
                // Not sure how one can cast to the precise type here..
                d.data = xx (r.buffer.data + r.bufferHead);
                Advance( r, d.count * tia.element_type.runtime_size );
            }
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
        // TODO We wanna have some default implementation for pointers (coherent with the behaviour for strings / arrays)
        #assert false "Not implemented. You must provide your own Reflect() overload for this type.";
    }

    return .Ok;
}

STR


#scope_file

BinaryTypeInfo :: struct
{

}
