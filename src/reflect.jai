#import "Compiler";
#import "Bucket_Array";
#import "Math";

#load "basic.jai";
#load "datatypes.jai";


Reflector :: struct ($IsReading: bool)
{
    IsWriting :: !IsReading;

    error: ReflectResult = ReflectOk;
}

ReflectResult :: enum
{
    Ok;
    Overflow;

    SomeError;
}
ReflectOk :: ReflectResult.Ok;

// TODO Store the code location of the piece of data causing the error
SetError :: ( error: ReflectResult, r: *Reflector )
{
    // Only remember the first error location
    if r.error != ReflectOk
        r.error = error;
}

#if 0
{
    // This seems to allow creating a specific overload for structs without using #modify
    // TODO I have the feeling I should be able to do everything via a macro that looks something like this (but perhaps passing a code node)
    // TODO Can functions & macros be part of the same overload set!? (looks like in principle they could..)

    // TODO Could we just '#insert GenReflectFunction()' in here? (removing the function header from that, just leaving the ReflectField calls..)
    // That'd mean that only the macros that are actually called would be generated, potentially saving compilation time
    Reflect :: ( d: *$T/interface struct {}, r: *Reflector ) -> ReflectResult #expand
    {
        st := cast(*Type_Info_Struct) type_info(T);
        // TODO When writing, *always order by offset in the source struct type* for cache friendliness
        // TODO When reading, the stream tells us the order of members to write to
        for m: st.members
        {
            // TODO This is a constant member, we should skip it.. (and if it has an id note, emit an error / warning)
            assert( m.offset_in_bytes >= 0, "Member '%' has offset %", m.name, m.offset_in_bytes );

            //if( ReflectMemberBegin( m, r ) )
            {
                GetMemberValueAs :: ( m: *Type_Info_Struct_Member, d: *$T/interface struct {}, $M: Type ) -> *M
                {
                    p := cast(*u8)d + m.offset_in_bytes;
                    return cast(*M)p;
                }

                // TODO How to dynamically cast this back to the actual member type so it goes to the appropriate Reflect() overload?
                M := get_root_type( m.type );
                print( "Member '%' is of type %\n", m.name, M );
                //result := Reflect( GetMemberValueAs( m, d, M ), r );
                //if( result != ReflectOk )
                //SetError( result, r );

                ////ReflectMemberEnd( m, r );
                //if( result != ReflectOk )
                //return result;
            }
        }

        return ReflectOk;
    }
}

// TODO When benchmarking, test making a custom overload for BinaryReflectors that tries to streamline this as much as possible
// NOTE Apparently there's a limit to macro recursion .. https://github.com/Jai-Community/Jai-Community-Library/wiki/Getting-Started#nested-macros
ReflectField :: ( field: Code, fieldId: u16, name: string, info: *ReflectedTypeInfo, r: *Reflector ) #expand
{
    result: ReflectResult = ReflectOk;

    //fieldOffset := ReflectFieldOffset( r );      
    if BeginReflectField( fieldId, name, info, r )  // *reflectedTypeInfo, attribs ) )
    {                                                     
        result = Reflect( #insert field, r );                        

        EndReflectField( fieldId, info, r );  // fieldOffset, &info, 
    }

    if result != ReflectOk
    {
        SetError( result, r );
        // Return from outer Reflect() function
        `return result;
    }
}


//
// BINARY
//

BinaryReflector :: struct( $IsReading2: bool )
{
    #as using reflector: Reflector( IsReading2 );

    bufferHead: s64;
}

BinaryReader :: struct
{
    #as using binary: BinaryReflector( true );

    // TODO Polymorph buffer type?
    buffer: [] u8;
}

BinaryWriter :: struct
{
    #as using binary: BinaryReflector( false );

    buffer: BufferBuilder( 1 * Megabytes );
}


ReflectedTypeInfo :: struct
{
    type:             Type;
    startOffset:      s64;
    totalSize:        s64;      // Packed into 64 bits together with fieldCount (so 48 bits max)
    currentFieldSize: s32;
    fieldCount:       u16;

    HeaderSize :: size_of(u64);
    TotalSizeBits :: (HeaderSize - size_of(type_of(fieldCount))) * 8;
    TotalSizeMax :: (1 << TotalSizeBits) - 1;
}

// TODO Begin/End ReflectType should also probably return a bool!?
BeginReflectType :: ( info: *ReflectedTypeInfo, type: Type, r: *BinaryReflector )
{
    #if r.IsReading
    {

    }
    else
    {
        info.type = type;
        info.startOffset = r.buffer.size;
        // make space to write a header later
        PushEmpty( *r.buffer, info.HeaderSize );
    }
}

EndReflectType :: ( info: *ReflectedTypeInfo, r: *BinaryReflector )
{
    #if r.IsReading
    {

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

        header: u64 = (info.fieldCount << info.TotalSizeBits) | ((cast(u64) info.totalSize) & info.TotalSizeMax);
        CopyFrom( *r.buffer, bytes_of( *header ), info.startOffset );
    }
}

BinaryField :: struct
{
    size:    s32;
    id:      u16;
    _padding: [2] u8;
}
#assert( offset_of( BinaryField, "_padding" ) == 6 );

BeginReflectField :: ( fieldId: u16, name: string, info: *ReflectedTypeInfo, r: *BinaryReflector ) -> bool
{
    #if r.IsReading
    {

    }
    else
    {
        assert( info.fieldCount < U16_MAX );

        info.fieldCount += 1;
        // Push a 0 placeholder for the totalSize (will be computed in EndReflectField)

    }
    return true;
}

EndReflectField :: ( fieldId: u16, info: *ReflectedTypeInfo, r: *BinaryReflector )
{

}
