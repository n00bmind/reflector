#import "Basic";
#import "json";

// TODO IMPORTANT Decide how we want to deal with field ids 
JsonReflector :: struct( $IsReading2: bool )
{
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
    depth: int;
}

JsonReader :: struct
{
    #as using base: JsonReflector( true );

    input: string;
}

JsonWriter :: struct
{
    #as using base: JsonReflector( false );

    output: string;
}



// TODO How do we avoid having to define these when they're not needed?
// Can we check for them with #exists or something?
BeginReflectType :: ( info: *void, type: Type, r: *JsonReflector ) -> bool
{
    if r.depth == 0
    {
        #if r.IsWriting
        {
            InitJsonWriter( xx r );
        }
        else
        {
            reader := cast(*JsonReader) r;
            if reader.input.data == null
            {
                assert( false && "'input' attribute must be set to point to the Json string to deserialize" );
                return false;
            }

            root := json_parse( reader.input );
            InitJsonReader( reader, root );
        }
    }

    r.depth += 1;
    return true;
}
EndReflectType :: ( info: *void, r: *JsonReflector )
{
    r.depth -= 1;

    if r.depth == 0
    {
        #if r.IsWriting
        {
            head := First( r.stack );
            if head
                r.output = json_write_pretty( head.value );
        }
    }
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
        assert( obj && "Current head is not a Json object" );

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


Push :: ( using r: *JsonReflector, value: *json_value_s )
{
    head = Push( *stack );
    head.value = value;
}

Pop :: ( using r: *JsonReflector )
{
    assert( stack.count != 0 && "JsonReflector stack underrun" );
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


#scope_module

InitJsonReader :: ( using r: *JsonReader, root: *json_value_s )
{
    stack.count = 0;

    assert( root != null );
    Push( r, root );
}

InitJsonWriter :: ( using r: *JsonWriter )
{
    stack.count = 0;

    // Create an empty root object and add it to the stack
    obj := New( json_object_s,, allocator = temp );

    root := New( json_value_s,, allocator = temp );
    root.* = .{ obj, .json_type_object };

    Push( r, root );
}

FindChild :: ( name: string, obj: *json_object_s ) -> *json_value_s
{
    child := obj.start;
    while child
    {
        childName := string.{ xx child.name.string_size, child.name.str };
        if childName == name 
            return child.value;

        child = child.next;
    }
    return null;
}


// TODO See how could make this part of the Reflector (struct) interface,
// so that the plugin knows what to insert for each Reflector subtype
JsonReflectorStrings :: #string STR

#import "json";

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
    // Note that according to how_to 100 though, this #run should only be invoked once for each type we pass in $T
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
    #if T == bool
    {
        #if r.IsWriting
        {
            r.head.value.* = .{ null, ifx d.* then .json_type_true else .json_type_false };
        }
        else
        {
            if json_value_is_true( r.head.value )
                d.* = true;
            else if json_value_is_false( r.head.value )
                d.* = false;
            else
                return .BadData;
        }
    }
    else #if #run IsIntegralType( T )
    {
        #run CheckSpecifiedEnumType( T );

        #if r.IsWriting
        {
            str: string;
            #if #run IsEnumType( T )
            {
                ST :: #run GetStorageType( T );
                str = tprint( "%", cast(ST) d.* );
            }
            else
                str = tprint( "%", d.* );
            numValue := New( json_number_s,, allocator = temp );
            numValue.* = .{ str.data, xx str.count };

            r.head.value.* = .{ numValue, .json_type_number };
        }
        else
        {
            numValue := json_value_as_number( r.head.value );
            if !numValue
                return .BadData;

            numStr := string.{ xx numValue.number_size, numValue.number };

            ST :: #run GetStorageType( T );
            num, ok := string_to_int( numStr, 10, ST );
            if ok
                d.* = xx num;
            else
                return.BadData;
        }
    }
    else #if #run IsFloatType( T )
    {
        #if r.IsWriting
        {
            str := tprint( "%", d.* );
            numValue := New( json_number_s,, allocator = temp );
            numValue.* = .{ str.data, xx str.count };

            r.head.value.* = .{ numValue, .json_type_number };
        }
        else
        {
            numValue := json_value_as_number( r.head.value );
            if !numValue
                return .BadData;

            numStr := string.{ xx numValue.number_size, numValue.number };
            num, ok := cast(T) string_to_float64( numStr );

            if ok
                d.* = num;
            else
                return.BadData;
        }
    }
    else #if T == string
    {
        #if r.IsWriting
        {
            strValue := New( json_string_s,, allocator = temp );
            strValue.* = .{ d.data, xx d.count };

            r.head.value.* = .{ strValue, .json_type_string };
        }
        else
        {
            strValue := json_value_as_string( r.head.value );
            if !strValue
                return .BadData;

            d.* = .{ xx strValue.string_size, strValue.str };
        }
    }
    else #if #run IsArrayType( T )
    {
        #if r.IsWriting
        {
            arrayValue := New( json_array_s,, allocator = temp );

            prev: *json_array_element_s;
            for d.*
            {
                // Push a blank value to reflect into to the stack
                itValue := NewEmptyObjValue();
                Push( r, itValue );

                result := Reflect( *it, r );
                if result != .Ok
                    return result;

                itElem := New( json_array_element_s,, allocator = temp );
                itElem.* = .{ itValue, null };

                if it_index == 0
                    arrayValue.start = itElem;
                else
                    prev.next = itElem;

                Pop( r );

                prev = itElem;
            }

            arrayValue.length = xx d.count;
            r.head.value.* = .{ arrayValue, .json_type_array };
        }
        else
        {
            arrayValue := json_value_as_array( r.head.value );
            if !arrayValue
                return .BadData;

            count: int = xx arrayValue.length;
            #if #run IsFixedArrayType( T )
            {
                // TODO Do we want to be more fault tolerant here?
                if count != d.count
                    return .BadData;
            }
            else
            {
                Reset( d, count, false );
            }

            itElem := arrayValue.start;
            for * d.*
            {
                if !itElem
                    return .BadData;

                Push( r, itElem.value );

                result := Reflect( it, r );
                if result != .Ok
                    return result;

                Pop( r );
                itElem = itElem.next;
            }
        }
    }

    return .Ok;
}

STR

