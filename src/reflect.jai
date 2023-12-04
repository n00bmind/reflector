#import "Compiler";

Reflector :: struct ($IsReading: bool)
{
    IsWriting :: !IsReading;


}

ReflectResult :: enum
{
    Ok;
}
ReflectOk :: ReflectResult.Ok;


// This seems to allow creating a specific overload for structs without using #modify
Reflect :: ( d: *$T/interface struct {}, r: *Reflector ) -> ReflectResult
{
    st := cast(*Type_Info_Struct) type_info(T);
    // TODO When writing, follow the order in the notes
    // TODO When reading, the stream tells us the order of members to write to
    for m: st.members
    {
        // TODO These is a constant member, we should skip it.. (and if it has an id note, emit an error / warning)
        assert( m.offset_in_bytes >= 0, "Member '%' has offset %", m.name, m.offset_in_bytes );

        //if( ReflectMemberBegin( m, r ) )
        {
            GetMemberValueAs :: ( m: *Type_Info_Struct_Member, d: *$T/interface struct {}, $M: Type ) -> *M
            {
                p := cast(*u8)d + m.offset_in_bytes;
                return cast(*M)p;
            }

            // TODO How to dynamically cast this back to the actual member type so it goes to the appropriate Reflect() overload?
            M := get_type( m.type );
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


//
// BINARY
//

BinaryReflector :: struct( $IsReading: bool )
{
    #as using base: Reflector( IsReading );

    // TODO Polymorph buffer type?
    buffer:     [] u8;
    bufferHead: s64;
}

BinaryReader :: BinaryReflector( true );
BinaryWriter :: BinaryReflector( false );


