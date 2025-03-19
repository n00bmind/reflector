#import "Basic";
#import "json";

// TODO IMPORTANT Decide whether we want to deal with field ids in some way, or just provide this as "example code"

JsonReflector :: struct( $IsReading2: bool )
{
    // TODO Eliminate the "type info" parameter from the root polymorphic Reflector, and let each implementation deal with that
    #as using reflector: Reflector( void, IsReading2 );

    StackEntry :: struct 
    {
        value: *json_value_s;
        // Either 'value' is of type json_type_object, or this must be null
        lastChild: *json_object_element_s;
    }

    // TODO Switch to our own simple bucket array?
    stack: [..] StackEntry;
    // NOTE Cached pointer to the last entry in the stack above (unstable, dont store!)
    head: *StackEntry;
}

JsonReader :: struct
{
    #as using base: JsonReflector( true );

}

JsonWriter :: struct
{
    #as using base: JsonReflector( false );

    builder: String_Builder;
    debugOutput: string;
}


// TODO How do we avoid having to define these when they're not needed?
// Can we check for them with #exists or something?
BeginReflectType :: ( info: *void, type: Type, r: *JsonReflector ) -> bool
{
    return true;
}
EndReflectType :: ( info: *void, r: *JsonReflector )
{
}


BeginReflectField :: ( fieldId: u16, name: string, offsetFromParent: s64, info: *void, r: *JsonReflector ) -> bool
{
    #if r.IsWriting
    {
        // Add a child to current parent object value
        obj := json_value_as_object( r.head.value );

        // If the current value has the dummy sentinel, add a real one
        if( obj == *emptyObj )
        {
            obj = New( json_object_s,, allocator = temp );
            r.head.value.* = .{ obj, .json_type_object };
            r.head.lastChild = null;
        }

        // Allocate a new copy of the template empty value, so we can keep modifying it as we go along
        val := NewEmptyObjValue();
        str := New( json_string_s,, allocator = temp );
        str.* = .{ name.data, xx name.count };

        e := New( json_object_element_s,, allocator = temp );
        e.* = .{ str, val, null };

        if r.head.lastChild 
            r.head.lastChild.next = e;
        else
            obj.start = e;

        obj.length += 1;
        r.head.lastChild = e;

        Push( r, val );

        return true;
    }
    else
    {
        // Find child with given name under current root object
        obj := json_value_as_object( r.head.value );
        assert( obj ); //, "Current head is not a Json object" );

        // TODO Probably would want to accelerate this with a hashtable or whatever
        child := FindChild( name, obj );
        if child 
            Push( r, child );

        return child != null;
    }
}

EndReflectField :: ( fieldId: u16, info: *void, r: *JsonReflector )
{
    Pop( r );
}


#scope_module

// TODO Embed in the serialisation logic?
InitJsonWriter :: ( using r: *JsonWriter )
{
    // Create an empty root object and add it to the stack
    obj := New( json_object_s,, allocator = temp );

    root := New( json_value_s,, allocator = temp );
    root.* = .{ obj, .json_type_object };

    Push( r, root );
}

// TODO How do we indicate / invoke any custom init logic that needs to happen like this?
// TODO Overload with something that just takes in json text
InitJsonReader :: ( using r: *JsonReader, root: *json_value_s )
{
    assert( root );
    Push( r, root );
}

Push :: ( using r: *JsonReflector, value: *json_value_s )
{
    newHead := Push( *stack );
    newHead.value = value;
}

Pop :: ( using r: *JsonReflector )
{
    assert( stack.count != 0 ); //, "JsonReflector stack underrun" );
    Pop( *stack );
    head = Last( stack );
}

emptyObj := json_object_s.{};
NewEmptyObjValue :: () -> *json_value_s
{
    val := New( json_value_s,, allocator = temp );
    val.* = .{ *emptyObj, .json_type_object };
    return val;
}

FindChild :: ( name: string, obj: *json_object_s ) -> *json_value_s
{
    child := obj.start;
    while child
    {
        if( child.name.str == name )
            return child.value;

        child = child.next;
    }
    return null;
}


// TODO See how could make this part of the Reflector (struct) interface,
// so that the plugin knows what to insert for each Reflector subtype
JsonReflectorStrings :: #string STR

// TODO Declaring this should be redundant once we are allowed to define a "root" Reflect() for type Reflector
// NOTE This overload also needs to be inserted, because it calls into the "root" ReflectField, which is also inserted
Reflect :: ( d: *$T, r: *JsonReflector ) -> ReflectResult
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

Reflect :: inline ( d: *$T, r: *JsonReflector ) -> ReflectResult #expand
#modify
{
    ti := cast(*Type_Info) T;
    return ti.type != .STRUCT;
}
// TODO This body should belong in a function called ReflectPrimitive, and we should be calling into that automatically
// from reflect.jai from a Reflect() overload with a #modify block like the one just above
// TODO I suppose the same issue with ambiguity that we have with the struct Reflect applies here..
{
    return .Ok;
}

STR
