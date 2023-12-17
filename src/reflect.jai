#import "Compiler";

Reflector :: struct ($IsReading: bool)
{
    IsWriting :: !IsReading;


}

ReflectResult :: enum
{
    Ok;
    SomeError;
}
ReflectOk :: ReflectResult.Ok;


#if 0
{
    // This seems to allow creating a specific overload for structs without using #modify
    // TODO I have the feeling I should be able to do everything via a macro that looks something like this (but perhaps passing a code node)
    // TODO Can functions & macros be part of the same overload set!? (looks like in principle they could..)
    Reflect :: ( d: *$T/interface struct {}, r: *Reflector ) -> ReflectResult #expand
    {
        st := cast(*Type_Info_Struct) type_info(T);
        // TODO When writing, follow the order in the notes
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
}

// TODO Apparently there's a limit to macro recursion .. https://github.com/Jai-Community/Jai-Community-Library/wiki/Getting-Started#nested-macros
ReflectField :: ( field: Code, r: *Reflector ) -> ReflectResult #expand
{
    print( "Got field: %\n", #insert field );
    result := Reflect( #insert field, r );
    // Return from outer Reflect() function
    `return result;
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


