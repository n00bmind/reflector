#import "Basic";

/* a JSON value. */
json_value_s :: struct
{
    /* a pointer to either a json_string_s, json_number_s, json_object_s, or. */
    /* json_array_s. Should be cast to the appropriate struct type based on what. */
    /* the type of this value is. */
    payload: *void;
    /* must be one of json_type_e. If type is json_type_true, json_type_false, or. */
    /* json_type_null, payload will be NULL. */
    type: json_type_e;
}

/* The various types JSON values can be. Used to identify what a value is. */
json_type_e :: enum
{
    json_type_null;
    json_type_object;
    json_type_array;
    json_type_string;
    json_type_number;
    json_type_true;
    json_type_false;
}

/* a JSON object value. */
json_object_s :: struct
{
    /* a linked list of the elements in the object. */
    start: *json_object_element_s;
    /* the number of elements in the object. */
    length: u64;
}

/* an element of a JSON object. */
json_object_element_s :: struct
{
    /* the name of this element. */
    name: *json_string_s;
    /* the value of this element. */
    value: *json_value_s;
    /* the next object element (can be NULL if the last element in the object). */
    next: *json_object_element_s;
}

/* a JSON array value. */
json_array_s :: struct
{
    /* a linked list of the elements in the array. */
    start: *json_array_element_s;
    /* the number of elements in the array. */
    length: u64;
}

/* an element of a JSON array. */
json_array_element_s :: struct
{
    /* the value of this element. */
    value: *json_value_s;
    /* the next array element (can be NULL if the last element in the array). */
    next: *json_array_element_s;
}

/* A JSON number value. */
// TODO Probably will want to union this with the cached integer value
json_number_s :: struct
{
    /* ASCII string containing representation of the number. */
    number: *u8;
    /* the size (in bytes) of the number. */
    number_size: u64;
}

/* A JSON string value. */
json_string_s :: struct
{
    /* utf-8 string */
    str: *u8;
    /* The size (in bytes) of the string */
    string_size: u64;
}

/* A JSON string value (extended). */
json_string_ex_s :: struct
{
    /* The JSON string this extends. */
    using base: json_string_s;
    /* The character offset for the value in the JSON input. */
    offset: u64;
    /* The line number for the value in the JSON input. */
    line_no: u64;
    /* The row number for the value in the JSON input, in bytes. */
    row_no: u64;
}


json_parse_flags_e :: enum_flags
{
    json_parse_flags_default :: 0;
    /* allow trailing commas in objects and arrays. For example, both [true,] and
    {"a" : null,} would be allowed with this option on. */
    json_parse_flags_allow_trailing_comma :: 0x1;
    /* allow unquoted keys for objects. For example, {a : null} would be allowed
    with this option on. */
    json_parse_flags_allow_unquoted_keys :: 0x2;
    /* allow a global unbracketed object. For example, a : null, b : true, c : {}
    would be allowed with this option on. */
    json_parse_flags_allow_global_object :: 0x4;
    /* allow objects to use '=' instead of ':' between key/value pairs. For
    example, a = null, b : true would be allowed with this option on. */
    json_parse_flags_allow_equals_in_object :: 0x8;
    /* allow that objects don't have to have comma separators between key/value pairs. */
    json_parse_flags_allow_no_commas :: 0x10;
    /* allow c-style comments (either variants) to be ignored in the input JSON file. */
    json_parse_flags_allow_c_style_comments :: 0x20;
    /* deprecated flag, unused. */
    json_parse_flags_deprecated :: 0x40;
    /* record location information for each value. */
    json_parse_flags_allow_location_information :: 0x80;
    /* allow strings to be 'single quoted'. */
    json_parse_flags_allow_single_quoted_strings :: 0x100;
    /* allow numbers to be hexadecimal. */
    json_parse_flags_allow_hexadecimal_numbers :: 0x200;
    /* allow numbers like +123 to be parsed. */
    json_parse_flags_allow_leading_plus_sign :: 0x400;
    /* allow numbers like .0123 or 123. to be parsed. */
    json_parse_flags_allow_leading_or_trailing_decimal_point :: 0x800;
    /* allow Infinity, -Infinity, NaN, -NaN. */
    json_parse_flags_allow_inf_and_nan :: 0x1000;
    /* allow multi line string values. */
    json_parse_flags_allow_multi_line_strings :: 0x2000;
    /* allow simplified JSON to be parsed. Simplified JSON is an enabling of a set of other parsing options. */
    json_parse_flags_allow_simplified_json ::
        (json_parse_flags_allow_trailing_comma |
        json_parse_flags_allow_unquoted_keys |
        json_parse_flags_allow_global_object |
        json_parse_flags_allow_equals_in_object |
        json_parse_flags_allow_no_commas);
    /* allow JSON5 to be parsed. JSON5 is an enabling of a set of other parsing options. */
    json_parse_flags_allow_json5 ::
        (json_parse_flags_allow_trailing_comma |
        json_parse_flags_allow_unquoted_keys |
        json_parse_flags_allow_c_style_comments |
        json_parse_flags_allow_single_quoted_strings |
        json_parse_flags_allow_hexadecimal_numbers |
        json_parse_flags_allow_leading_plus_sign |
        json_parse_flags_allow_leading_or_trailing_decimal_point |
        json_parse_flags_allow_inf_and_nan |
        json_parse_flags_allow_multi_line_strings);
}

/* error report from json_parse(). */
json_parse_result_s :: struct
{
    /* the error code (one of json_parse_error_e). */
    error: json_parse_error_e;
    /* the character offset for the error in the JSON input. */
    error_offset: u64;
    /* the line number for the error in the JSON input. */
    error_line_no: u64;
    /* the row number for the error, in bytes. */
    error_row_no: u64;
}

/* a parsing error code. */
json_parse_error_e :: enum
{
    /* no error occurred (huzzah!). */
    json_parse_error_none :: 0;
    /* expected either a comma or a closing '}' or ']' to close an object or. */ /* array! */
    json_parse_error_expected_comma_or_closing_bracket;
    /* colon separating name/value pair was missing! */
    json_parse_error_expected_colon;
    /* expected string to begin with '"'! */
    json_parse_error_expected_opening_quote;
    /* invalid escaped sequence in string! */
    json_parse_error_invalid_string_escape_sequence;
    /* invalid number format! */
    json_parse_error_invalid_number_format;
    /* invalid value! */
    json_parse_error_invalid_value;
    /* reached end of buffer before object/array was complete! */
    json_parse_error_premature_end_of_buffer;
    /* string was malformed! */
    json_parse_error_invalid_string;
    /* a call to malloc, or a user provider allocator, failed. */
    json_parse_error_allocator_failed;
    /* the JSON input had unexpected trailing characters that weren't part of the. JSON value. */
    json_parse_error_unexpected_trailing_characters;
    /* catch-all error for everything else that exploded (real bad chi!). */
    json_parse_error_unknown;
};


//// Reading

AllocProc :: #type ( user_data: *void, size: u64 ) -> *void;
FreeProc :: #type ( p: *void );

/* Parse a JSON text file, returning a pointer to the root of the JSON
 * structure. json_parse performs 1 call to malloc for the entire encoding.
 * Returns 0 if an error occurred (malformed JSON input, or malloc failed). */
json_parse :: ( src: string ) -> *json_value_s
{
    return json_parse( src.data, xx src.count, .json_parse_flags_default, null, null, null );
}
json_parse :: ( src: *void, src_size: u64 ) -> *json_value_s
{
    return json_parse( src, src_size, .json_parse_flags_default, null, null, null );
}

/* Parse a JSON text file, returning a pointer to the root of the JSON
 * structure. json_parse performs 1 call to alloc_func_ptr for the entire
 * encoding. Returns 0 if an error occurred (malformed JSON input, or malloc
 * failed). If an error occurred, the result struct (if not NULL) will explain
 * the type of error, and the location in the input it occurred. If
 * alloc_func_ptr is null then malloc is used. */

// TODO Make some of these args have defaults
json_parse :: ( src: *void, src_size: u64, flags_bitset: json_parse_flags_e, alloc_func_ptr: AllocProc, user_data: *void,
                result: *json_parse_result_s ) -> *json_value_s
{
    state: json_parse_state_s;
    allocation: *void;
    value: *json_value_s;
    total_size: u64;
    input_error: int;

    if result
    {
        result.error = .json_parse_error_none;
        result.error_offset = 0;
        result.error_line_no = 0;
        result.error_row_no = 0;
    }

    if null == src
    {
        /* invalid src pointer was null! */
        return null;
    }

    state.src = cast(*u8)src;
    state.size = src_size;
    state.offset = 0;
    state.line_no = 1;
    state.line_offset = 0;
    state.error = .json_parse_error_none;
    state.dom_size = 0;
    state.data_size = 0;
    state.flags_bitset = flags_bitset;

    // TODO This "measure" then actually parse approach is.. not great
    // At the very least this should return a list of tokens in temp memory so that we parse based on that
    input_error = json_get_value_size( *state, cast(int)(.json_parse_flags_allow_global_object & state.flags_bitset) );

    if 0 == input_error
    {
        json_skip_all_skippables( *state );

        if state.offset != state.size
        {
            /* our parsing didn't have an error, but there are characters remaining in
            * the input that weren't part of the JSON! */
            state.error = .json_parse_error_unexpected_trailing_characters;
            input_error = 1;
        }
    }

    if input_error
    {
        /* parsing value's size failed (most likely an invalid JSON DOM!). */
        if result
        {
            result.error = state.error;
            result.error_offset = state.offset;
            result.error_line_no = state.line_no;
            result.error_row_no = state.offset - state.line_offset;
        }
        return null;
    }

    /* our total allocation is the combination of the dom and data sizes (we. */
    /* first encode the structure of the JSON, and then the data referenced by. */
    /* the JSON values). */
    total_size = state.dom_size + state.data_size;

    if alloc_func_ptr
        allocation = alloc_func_ptr( user_data, total_size );
    else
        allocation = alloc( xx total_size );

    if null == allocation
    {
        /* malloc failed! */
        if result
        {
            result.error = .json_parse_error_allocator_failed;
            result.error_offset = 0;
            result.error_line_no = 0;
            result.error_row_no = 0;
        }

        return null;
    }

    /* reset offset so we can reuse it. */
    state.offset = 0;

    /* reset the line information so we can reuse it. */
    state.line_no = 1;
    state.line_offset = 0;

    state.dom = cast(*u8)allocation;
    state.data = state.dom + state.dom_size;

    if .json_parse_flags_allow_location_information & state.flags_bitset
    {
        value_ex: *json_value_ex_s = cast(*json_value_ex_s)state.dom;
        state.dom += size_of(json_value_ex_s);

        value_ex.offset = state.offset;
        value_ex.line_no = state.line_no;
        value_ex.row_no = state.offset - state.line_offset;

        value = *(value_ex.value);
    } else {
        value = cast(*json_value_s)state.dom;
        state.dom += size_of(json_value_s);
    }

    json_parse_value( *state, cast(int)(.json_parse_flags_allow_global_object & state.flags_bitset), value );

    return cast(*json_value_s)allocation;
}


json_value_as_string :: ( value: *json_value_s ) -> *json_string_s
{
    if value.type != .json_type_string
        return null;

    return cast(*json_string_s)value.payload;
}

json_value_as_number :: ( value: *json_value_s ) -> *json_number_s
{
    if value.type != .json_type_number
        return null;

    return cast(*json_number_s)value.payload;
}

json_value_as_object :: ( value: *json_value_s ) -> *json_object_s
{
    if value.type != .json_type_object
        return null;

    return cast(*json_object_s)value.payload;
}

json_value_as_array :: ( value: *json_value_s ) -> *json_array_s
{
    if value.type != .json_type_array
        return null;

    return cast(*json_array_s)value.payload;
}

json_value_is_true :: ( value: *json_value_s ) -> bool
{
    return value.type == .json_type_true;
}

json_value_is_false :: ( value: *json_value_s ) -> bool
{
    return value.type == .json_type_false;
}

json_value_is_null :: ( value: *json_value_s ) -> bool
{
    return value.type == .json_type_null;
}


//// Writing

json_write_minified :: ( value: *json_value_s ) -> string
{
    if null == value
        return "";

    builder: String_Builder;
    builder.allocator = temp;

    ok := json_write_minified_value( value, *builder );

    if !ok
        return "";

    // TODO Support passing an allocator directly instead of always relying on the context
     // TODO Doesn't this ',,' thingy already do that though?
    return builder_to_string( *builder, do_reset = false );
}

json_write_pretty :: ( value: *json_value_s, indent := "  ", newline := "\n" ) -> string
{
    if null == value
        return "";

    builder: String_Builder;
    builder.allocator = temp;

    ok := json_write_pretty_value( value, 0, indent, newline, *builder );

    if !ok
        return "";

    return builder_to_string( *builder, do_reset = false );
}



#scope_module

/* a JSON value (extended). */
json_value_ex_s :: struct
{
    /* the JSON value this extends. */
    using value: json_value_s;
    /* the character offset for the value in the JSON input. */
    offset: u64;
    /* the line number for the value in the JSON input. */
    line_no: u64;
    /* the row number for the value in the JSON input, in bytes. */
    row_no: u64;
}

json_parse_state_s :: struct
{
    src: *u8;
    size: u64;
    offset: u64;
    flags_bitset: json_parse_flags_e;
    data: *u8;
    dom: *u8;
    dom_size: u64;
    data_size: u64;
    line_no: u64;     /* line counter for error reporting. */
    line_offset: u64; /* (offset-line_offset) is the character number (in bytes). */
    error: json_parse_error_e;
}


json_get_value_size :: ( state: *json_parse_state_s, is_global_object: int ) -> int
{
    flags_bitset := state.flags_bitset;
    src := state.src;
    size := state.size;
    offset: u64;

    if .json_parse_flags_allow_location_information & flags_bitset
        state.dom_size += size_of(json_value_ex_s);
    else
        state.dom_size += size_of(json_value_s);

    if is_global_object
        return json_get_object_size( state, /* is_global_object = */ 1 );
    else
    {
        if json_skip_all_skippables( state )
        {
            state.error = .json_parse_error_premature_end_of_buffer;
            return 1;
        }

        /* can cache offset now. */
        offset = state.offset;

        if src[offset] ==
        {
            case #char "\"";
                return json_get_string_size( state, 0 );
            case #char "'";
                if .json_parse_flags_allow_single_quoted_strings & flags_bitset
                    return json_get_string_size( state, 0 );
                else
                {
                    /* invalid value! */
                    state.error = .json_parse_error_invalid_value;
                    return 1;
                }
            case #char "{";
                return json_get_object_size( state, /* is_global_object = */ 0 );
            case #char "[";
                return json_get_array_size( state );
            case #char "-"; #through;
            case #char "0"; #through;
            case #char "1"; #through;
            case #char "2"; #through;
            case #char "3"; #through;
            case #char "4"; #through;
            case #char "5"; #through;
            case #char "6"; #through;
            case #char "7"; #through;
            case #char "8"; #through;
            case #char "9";
                return json_get_number_size( state );
            case #char "+";
                if .json_parse_flags_allow_leading_plus_sign & flags_bitset
                    return json_get_number_size( state );
                else
                {
                    /* invalid value! */
                    state.error = .json_parse_error_invalid_number_format;
                    return 1;
                }
            case #char ".";
                if .json_parse_flags_allow_leading_or_trailing_decimal_point & flags_bitset
                    return json_get_number_size( state );
                else
                {
                    /* invalid value! */
                    state.error = .json_parse_error_invalid_number_format;
                    return 1;
                }
            case;
                if (offset + 4) <= size && #char "t" == src[offset + 0]
                    && #char "r" == src[offset + 1] && #char "u" == src[offset + 2]
                    && #char "e" == src[offset + 3] {
                    state.offset += 4;
                    return 0;
                }
                else if (offset + 5) <= size && #char "f" == src[offset + 0]
                    && #char "a" == src[offset + 1] && #char "l" == src[offset + 2]
                    && #char "s" == src[offset + 3] && #char "e" == src[offset + 4] {
                    state.offset += 5;
                    return 0;
                }
                else if (offset + 4) <= size && #char "n" == state.src[offset + 0]
                    && #char "u" == state.src[offset + 1]
                    && #char "l" == state.src[offset + 2]
                    && #char "l" == state.src[offset + 3] {
                    state.offset += 4;
                    return 0;
                }
                else if (.json_parse_flags_allow_inf_and_nan & flags_bitset)
                    && (offset + 3) <= size && #char "N" == src[offset + 0]
                    && #char "a" == src[offset + 1] && #char "N" == src[offset + 2] {
                    return json_get_number_size( state );
                }
                else if (.json_parse_flags_allow_inf_and_nan & flags_bitset)
                    && (offset + 8) <= size && #char "I" == src[offset + 0]
                    && #char "n" == src[offset + 1] && #char "f" == src[offset + 2]
                    && #char "i" == src[offset + 3] && #char "n" == src[offset + 4]
                    && #char "i" == src[offset + 5] && #char "t" == src[offset + 6]
                    && #char "y" == src[offset + 7] {
                    return json_get_number_size( state );
                }

                /* invalid value! */
                state.error = .json_parse_error_invalid_value;
                return 1;
        }
    }
}

json_parse_value :: ( state: *json_parse_state_s, is_global_object: int, value: *json_value_s )
{
    flags_bitset := state.flags_bitset;
    src := state.src;
    size := state.size;
    offset: u64;

    json_skip_all_skippables( state );

    /* cache offset now. */
    offset = state.offset;

    if is_global_object
    {
        value.type = .json_type_object;
        value.payload = state.dom;
        state.dom += size_of(json_object_s);
        json_parse_object( state, /* is_global_object = */ 1, cast(*json_object_s)value.payload );
    }
    else
    {
        if src[offset] ==
        {
            case #char "\""; #through;
            case #char "'";
                value.type = .json_type_string;
                value.payload = state.dom;
                state.dom += size_of(json_string_s);
                json_parse_string( state, cast(*json_string_s)value.payload );
            case #char "{";
                value.type = .json_type_object;
                value.payload = state.dom;
                state.dom += size_of(json_object_s);
                json_parse_object( state, /* is_global_object = */ 0, cast(*json_object_s)value.payload );
            case #char "[";
                value.type = .json_type_array;
                value.payload = state.dom;
                state.dom += size_of(json_array_s);
                json_parse_array( state, cast(*json_array_s)value.payload );

            case #char "-"; #through;
            case #char "+"; #through;
            case #char "0"; #through;
            case #char "1"; #through;
            case #char "2"; #through;
            case #char "3"; #through;
            case #char "4"; #through;
            case #char "5"; #through;
            case #char "6"; #through;
            case #char "7"; #through;
            case #char "8"; #through;
            case #char "9"; #through;
            case #char ".";
                value.type = .json_type_number;
                value.payload = state.dom;
                state.dom += size_of(json_number_s);
                json_parse_number( state, cast(*json_number_s)value.payload );

            case;
                if (offset + 4) <= size && #char "t" == src[offset + 0] && #char "r" == src[offset + 1]
                    && #char "u" == src[offset + 2] && #char "e" == src[offset + 3]
                {
                    value.type = .json_type_true;
                    value.payload = null;
                    state.offset += 4;
                }
                else if (offset + 5) <= size && #char "f" == src[offset + 0] && #char "a" == src[offset + 1]
                    && #char "l" == src[offset + 2] && #char "s" == src[offset + 3] && #char "e" == src[offset + 4]
                {
                    value.type = .json_type_false;
                    value.payload = null;
                    state.offset += 5;
                }
                else if (offset + 4) <= size && #char "n" == src[offset + 0] && #char "u" == src[offset + 1]
                    && #char "l" == src[offset + 2] && #char "l" == src[offset + 3]
                {
                    value.type = .json_type_null;
                    value.payload = null;
                    state.offset += 4;
                }
                else if (.json_parse_flags_allow_inf_and_nan & flags_bitset) && (offset + 3) <= size
                    && #char "N" == src[offset + 0] && #char "a" == src[offset + 1] && #char "N" == src[offset + 2]
                {
                    value.type = .json_type_number;
                    value.payload = state.dom;
                    state.dom += size_of(json_number_s);
                    json_parse_number( state, cast(*json_number_s)value.payload );
                }
                else if (.json_parse_flags_allow_inf_and_nan & flags_bitset) && (offset + 8) <= size
                    && #char "I" == src[offset + 0] && #char "n" == src[offset + 1] && #char "f" == src[offset + 2]
                    && #char "i" == src[offset + 3] && #char "n" == src[offset + 4] && #char "i" == src[offset + 5]
                    && #char "t" == src[offset + 6] && #char "y" == src[offset + 7]
                {
                    value.type = .json_type_number;
                    value.payload = state.dom;
                    state.dom += size_of(json_number_s);
                    json_parse_number( state, cast(*json_number_s)value.payload );
                }
        }
    }
}


json_get_object_size :: ( state: *json_parse_state_s, is_global_object: int ) -> int
{
    flags_bitset := state.flags_bitset;
    src := state.src;
    size := state.size;
    elements: u64 = 0;
    allow_comma: int = 0;
    found_closing_brace: int = 0;

    if is_global_object
    {
        /* if we found an opening '{' of an object, we actually have a normal JSON object at the root of the DOM... */
        if !json_skip_all_skippables( state ) && #char "{" == state.src[state.offset]
        {
            /* . and we don't actually have a global object after all! */
            is_global_object = 0;
        }
    }

    if !is_global_object
    {
        if #char "{" != src[state.offset]
        {
            state.error = .json_parse_error_unknown;
            return 1;
        }

        /* skip leading '{'. */
        state.offset += 1;
    }

    state.dom_size += size_of(json_object_s);

    if (state.offset == size) && !is_global_object
    {
        state.error = .json_parse_error_premature_end_of_buffer;
        return 1;
    }

    while state.offset < size
    {
        if !is_global_object
        {
            if json_skip_all_skippables( state )
            {
                state.error = .json_parse_error_premature_end_of_buffer;
                return 1;
            }

            if #char "}" == src[state.offset]
            {
                /* skip trailing '}'. */
                state.offset += 1;

                found_closing_brace = 1;

                /* finished the object! */
                break;
            }
        }
        else
        {
            /* we don't require brackets, so that means the object ends when the input
            * stream ends! */
            if json_skip_all_skippables( state )
                break;
        }

        /* if we parsed at least one element previously, grok for a comma. */
        if allow_comma
        {
            if #char "," == src[state.offset]
            {
                /* skip comma. */
                state.offset += 1;
                allow_comma = 0;
            }
            else if .json_parse_flags_allow_no_commas & flags_bitset
            {
                /* we don't require a comma, and we didn't find one, which is ok! */
                allow_comma = 0;
            }
            else
            {
                /* otherwise we are required to have a comma, and we found none. */
                state.error = .json_parse_error_expected_comma_or_closing_bracket;
                return 1;
            }

            if .json_parse_flags_allow_trailing_comma & flags_bitset
                continue;
            else
            {
                if json_skip_all_skippables( state )
                {
                    state.error = .json_parse_error_premature_end_of_buffer;
                    return 1;
                }
            }
        }

        if json_get_key_size( state )
        {
            /* key parsing failed! */
            state.error = .json_parse_error_invalid_string;
            return 1;
        }

        if json_skip_all_skippables( state )
        {
            state.error = .json_parse_error_premature_end_of_buffer;
            return 1;
        }

        if .json_parse_flags_allow_equals_in_object & flags_bitset
        {
            current := src[state.offset];
            if (#char ":" != current) && (#char "=" != current)
            {
                state.error = .json_parse_error_expected_colon;
                return 1;
            }
        }
        else
        {
            if #char ":" != src[state.offset]
            {
                state.error = .json_parse_error_expected_colon;
                return 1;
            }
        }

        /* skip colon. */
        state.offset += 1;

        if json_skip_all_skippables( state )
        {
            state.error = .json_parse_error_premature_end_of_buffer;
            return 1;
        }

        if json_get_value_size( state, /* is_global_object = */ 0 )
        {
            /* value parsing failed! */
            return 1;
        }

        /* successfully parsed a name/value pair! */
        elements += 1;
        allow_comma = 1;
    }

    if (state.offset == size) && !is_global_object && !found_closing_brace
    {
        state.error = .json_parse_error_premature_end_of_buffer;
        return 1;
    }

    state.dom_size += size_of(json_object_element_s) * elements;

    return 0;
}

json_get_key_size :: ( state: *json_parse_state_s ) -> int
{
    flags_bitset := state.flags_bitset;

    if .json_parse_flags_allow_unquoted_keys & flags_bitset
    {
        offset := state.offset;
        size := state.size;
        src := state.src;
        data_size := state.data_size;

        /* if we are allowing unquoted keys, first grok for a quote... */
        if #char "\"" == src[offset]
        {
            /* ... if we got a comma, just parse the key as a string as normal. */
            return json_get_string_size( state, 1 );
        }
        else if (.json_parse_flags_allow_single_quoted_strings & flags_bitset) && (#char "'" == src[offset])
        {
            /* ... if we got a comma, just parse the key as a string as normal. */
            return json_get_string_size(state, 1);
        }
        else
        {
            while (offset < size) && is_valid_unquoted_key_char(src[offset])
            {
                offset += 1;
                data_size += 1;
            }

            /* one more byte for null terminator ending the string! */
            data_size += 1;

            if .json_parse_flags_allow_location_information & flags_bitset
                state.dom_size += size_of(json_string_ex_s);
            else
                state.dom_size += size_of(json_string_s);

            /* update offset. */
            state.offset = offset;
            /* update data_size. */
            state.data_size = data_size;

            return 0;
        }
    }
    else
    {
        /* we are only allowed to have quoted keys, so just parse a string! */
        return json_get_string_size( state, 1 );
    }
}

json_parse_key :: ( state: *json_parse_state_s, str: *json_string_s )
{
    if .json_parse_flags_allow_unquoted_keys & state.flags_bitset
    {
        src := state.src;
        data := state.data;
        offset := state.offset;

        /* if we are allowing unquoted keys, check for quoted anyway... */
        if (#char "\"" == src[offset]) || (#char "'" == src[offset])
        {
            /* ... if we got a quote, just parse the key as a string as normal. */
            json_parse_string( state, str );
        }
        else
        {
            size: u64 = 0;
            str.str = state.data;

            while is_valid_unquoted_key_char( src[offset] )
            {
                data[size] = src[offset];
                size += 1;
                offset += 1;
            }

            /* add null terminator to string. */
            data[size] = 0;
            /* record the size of the string. */
            str.string_size = size;
            size += 1;
            /* move data along. */
            state.data += size;
            /* update offset. */
            state.offset = offset;
        }
    }
    else
    {
        /* we are only allowed to have quoted keys, so just parse a string! */
        json_parse_string( state, str );
    }
}

is_valid_unquoted_key_char :: ( c: int ) -> bool
{
    return (#char "0" <= c && c <= #char "9") || (#char "a" <= c && c <= #char "z")
        || (#char "A" <= c && c <= #char "Z") || (#char "_" == c);
}


json_parse_object :: ( state: *json_parse_state_s, is_global_object: int, object: *json_object_s )
{
    flags_bitset := state.flags_bitset;
    size := state.size;
    src := state.src;
    elements: u64 = 0;
    allow_comma: int = 0;
    previous: *json_object_element_s = null;

    if is_global_object
    {
        /* if we skipped some whitespace, and then found an opening '{' of an. */
        /* object, we actually have a normal JSON object at the root of the DOM...
        */
        if #char "{" == src[state.offset]
        {
            /* . and we don't actually have a global object after all! */
            is_global_object = 0;
        }
    }

    if !is_global_object
    {
        /* skip leading '{'. */
        state.offset += 1;
    }

    json_skip_all_skippables( state );

    /* reset elements. */
    elements = 0;

    while state.offset < size
    {
        element: *json_object_element_s = null;
        str: *json_string_s = null;
        value: *json_value_s = null;

        if !is_global_object
        {
            json_skip_all_skippables( state );

            if #char "}" == src[state.offset]
            {
                /* skip trailing '}'. */
                state.offset += 1;
                /* finished the object! */
                break;
            }
        }
        else
        {
            if json_skip_all_skippables( state )
            {
                /* global object ends when the file ends! */
                break;
            }
        }

        /* if we parsed at least one element previously, grok for a comma. */
        if allow_comma
        {
            if #char "," == src[state.offset]
            {
                /* skip comma. */
                state.offset += 1;
                allow_comma = 0;
                continue;
            }
        }

        element = cast(*json_object_element_s)state.dom;

        state.dom += size_of(json_object_element_s);

        if null == previous
            /* this is our first element, so record it in our object. */
            object.start = element;
        else
            previous.next = element;

        previous = element;

        if .json_parse_flags_allow_location_information & flags_bitset
        {
            string_ex: *json_string_ex_s = cast(*json_string_ex_s)state.dom;
            state.dom += size_of(json_string_ex_s);

            string_ex.offset = state.offset;
            string_ex.line_no = state.line_no;
            string_ex.row_no = state.offset - state.line_offset;

            str = *(string_ex.base);
        }
        else
        {
            str = cast(*json_string_s)state.dom;
            state.dom += size_of(json_string_s);
        }

        element.name = str;

        json_parse_key( state, str );
        json_skip_all_skippables( state );

        /* skip colon or equals. */
        state.offset += 1;

        json_skip_all_skippables( state );

        if .json_parse_flags_allow_location_information & flags_bitset
        {
            value_ex: *json_value_ex_s = cast(*json_value_ex_s)state.dom;
            state.dom += size_of(json_value_ex_s);

            value_ex.offset = state.offset;
            value_ex.line_no = state.line_no;
            value_ex.row_no = state.offset - state.line_offset;

            value = *(value_ex.value);
        }
        else
        {
            value = cast(*json_value_s)state.dom;
            state.dom += size_of(json_value_s);
        }

        element.value = value;

        json_parse_value( state, /* is_global_object = */ 0, value );

        /* successfully parsed a name/value pair! */
        elements += 1;
        allow_comma = 1;
    }

    /* if we had at least one element, end the linked list. */
    if previous
        previous.next = null;

    if (0 == elements)
        object.start = null;

    object.length = elements;
}

json_get_string_size :: ( state: *json_parse_state_s, is_key: u64 ) -> int
{
    offset := state.offset;
    size := state.size;
    data_size: u64 = 0;
    src := state.src;
    is_single_quote: bool = #char "'" == src[offset];
    quote_to_use: int = ifx is_single_quote then #char "'" else #char "\"";
    flags_bitset := state.flags_bitset;
    codepoint: u32;
    high_surrogate: u32 = 0;

    if (.json_parse_flags_allow_location_information & flags_bitset) != 0 && is_key != 0
        state.dom_size += size_of(json_string_ex_s);
    else
        state.dom_size += size_of(json_string_s);

    if #char "\"" != src[offset]
    {
        /* if we are allowed single quoted strings check for that too. */
        if !((.json_parse_flags_allow_single_quoted_strings & flags_bitset) && is_single_quote)
        {
            state.error = .json_parse_error_expected_opening_quote;
            state.offset = offset;
            return 1;
        }
    }

    /* skip leading '"' or '\''. */
    offset += 1;

    while (offset < size) && (quote_to_use != src[offset])
    {
        /* add space for the character. */
        data_size += 1;

        if src[offset] ==
        {
            case #char "\0"; #through;
            case #char "\t";
                state.error = .json_parse_error_invalid_string;
                state.offset = offset;
                return 1;
        }

        if #char "\\" == src[offset]
        {
            /* skip reverse solidus character. */
            offset += 1;

            if offset == size
            {
                state.error = .json_parse_error_premature_end_of_buffer;
                state.offset = offset;
                return 1;
            }

            if src[offset] ==
            {
                case;
                    state.error = .json_parse_error_invalid_string_escape_sequence;
                    state.offset = offset;
                    return 1;
                case #char "\""; #through;
                case #char "\\"; #through;
                case #char "/"; #through;
                case #char "b"; #through;
                case #char "f"; #through;
                case #char "n"; #through;
                case #char "r"; #through;
                case #char "t";
                    /* all valid characters! */
                    offset += 1;
                case #char "u";
                    if !(offset + 5 < size)
                    {
                        /* invalid escaped unicode sequence! */
                        state.error = .json_parse_error_invalid_string_escape_sequence;
                        state.offset = offset;
                        return 1;
                    }

                    codepoint = 0;
                    if !json_hexadecimal_value( *src[offset + 1], 4, *codepoint )
                    {
                        /* escaped unicode sequences must contain 4 hexadecimal digits! */
                        state.error = .json_parse_error_invalid_string_escape_sequence;
                        state.offset = offset;
                        return 1;
                    }

                    /* Valid sequence!
                    * see: https://en.wikipedia.org/wiki/UTF-8#Invalid_code_points.
                    *      1       7       U + 0000        U + 007F        0xxxxxxx.
                    *      2       11      U + 0080        U + 07FF        110xxxxx
                    * 10xxxxxx.
                    *      3       16      U + 0800        U + FFFF        1110xxxx
                    * 10xxxxxx        10xxxxxx.
                    *      4       21      U + 10000       U + 10FFFF      11110xxx
                    * 10xxxxxx        10xxxxxx        10xxxxxx.
                    * Note: the high and low surrogate halves used by UTF-16 (U+D800
                    * through U+DFFF) and code points not encodable by UTF-16 (those after
                    * U+10FFFF) are not legal Unicode values, and their UTF-8 encoding must
                    * be treated as an invalid byte sequence. */
                    if high_surrogate != 0
                    {
                        /* we previously read the high half of the \uxxxx\uxxxx pair, so now
                        * we expect the low half. */
                        if codepoint >= 0xdc00 && codepoint <= 0xdfff /* low surrogate range. */
                        {
                            data_size += 3;
                            high_surrogate = 0;
                        }
                        else
                        {
                            state.error = .json_parse_error_invalid_string_escape_sequence;
                            state.offset = offset;
                            return 1;
                        }
                    } else if codepoint <= 0x7f {
                        data_size += 0;
                    } else if codepoint <= 0x7ff {
                        data_size += 1;
                    }
                    else if codepoint >= 0xd800 && codepoint <= 0xdbff /* high surrogate range. */
                    {
                        /* The codepoint is the first half of a "utf-16 surrogate pair". so we
                        * need the other half for it to be valid: \uHHHH\uLLLL. */
                        if offset + 11 > size || #char "\\" != src[offset + 5] || #char "u" != src[offset + 6]
                        {
                            state.error = .json_parse_error_invalid_string_escape_sequence;
                            state.offset = offset;
                            return 1;
                        }
                        high_surrogate = codepoint;
                    }
                    else if codepoint >= 0xd800 && codepoint <= 0xdfff /* low surrogate range. */
                    {
                        /* we did not read the other half before. */
                        state.error = .json_parse_error_invalid_string_escape_sequence;
                        state.offset = offset;
                        return 1;
                    } else {
                        data_size += 2;
                    }
                    /* escaped codepoints after 0xffff are supported in json through utf-16
                    * surrogate pairs: \uD83D\uDD25 for U+1F525. */

                    offset += 5;
            }
        }
        else if (#char "\r" == src[offset]) || (#char "\n" == src[offset])
        {
            if !(.json_parse_flags_allow_multi_line_strings & flags_bitset)
            {
                /* invalid escaped unicode sequence! */
                state.error = .json_parse_error_invalid_string_escape_sequence;
                state.offset = offset;
                return 1;
            }

            offset += 1;
        }
        else
        {
            /* skip character (valid part of sequence). */
            offset += 1;
        }
    }

    /* If the offset is equal to the size, we had a non-terminated string! */
    if offset == size
    {
        state.error = .json_parse_error_premature_end_of_buffer;
        state.offset = offset - 1;
        return 1;
    }

    /* skip trailing '"' or '\''. */
    offset += 1;
    /* add enough space to store the string. */
    state.data_size += data_size;
    /* one more byte for null terminator ending the string! */
    state.data_size += 1;
    /* update offset. */
    state.offset = offset;

    return 0;
}

json_parse_string :: ( state: *json_parse_state_s, str: *json_string_s )
{
    offset := state.offset;
    bytes_written: u64 = 0;
    src := state.src;
    quote_to_use := ifx #char "'" == src[offset] then #char "'" else #char "\"";
    data := state.data;
    high_surrogate: u32 = 0;
    codepoint: u32;

    str.str = data;

    /* skip leading '"' or '\''. */
    offset += 1;

    while quote_to_use != src[offset]
    {
        if #char "\\" == src[offset]
        {
            /* skip the reverse solidus. */
            offset += 1;

            c := src[offset];
            offset += 1;
            if c ==
            {
                case;
                    return; /* we cannot ever reach here. */
                case #char "u";
                {
                    codepoint = 0;
                    ok := json_hexadecimal_value( *src[offset], 4, *codepoint );
                    /* this shouldn't happen as the value was already validated. */
                    assert( ok && "Failed to parse hexadecimal value" );

                    offset += 4;

                    if codepoint <= 0x7f
                    {
                        data[bytes_written] = cast(u8)codepoint; /* 0xxxxxxx. */
                        bytes_written += 1;
                    }
                    else if codepoint <= 0x7ff
                    {
                        data[bytes_written] = cast(u8)(0xc0 | (codepoint >> 6)); /* 110xxxxx. */
                        bytes_written += 1;
                        data[bytes_written] = cast(u8)(0x80 | (codepoint & 0x3f)); /* 10xxxxxx. */
                        bytes_written += 1;
                    }
                    else if codepoint >= 0xd800 && codepoint <= 0xdbff /* high surrogate. */
                    { 
                        high_surrogate = codepoint;
                        continue; /* we need the low half to form a complete codepoint. */
                    }
                    else if codepoint >= 0xdc00 && codepoint <= 0xdfff /* low surrogate. */
                    {
                        /* combine with the previously read half to obtain the complete
                        * codepoint. */
                        surrogate_offset: u32 = 0x10000 - cast(u32)(0xD800 << 10) - 0xDC00;
                        codepoint = (high_surrogate << 10) + codepoint + surrogate_offset;
                        high_surrogate = 0;
                        data[bytes_written] = cast(u8)(0xF0 | (codepoint >> 18)); /* 11110xxx. */
                        bytes_written += 1;
                        data[bytes_written] = cast(u8)(0x80 | ((codepoint >> 12) & 0x3f)); /* 10xxxxxx. */
                        bytes_written += 1;
                        data[bytes_written] = cast(u8)(0x80 | ((codepoint >> 6) & 0x3f)); /* 10xxxxxx. */
                        bytes_written += 1;
                        data[bytes_written] = cast(u8)(0x80 | (codepoint & 0x3f)); /* 10xxxxxx. */
                        bytes_written += 1;
                    }
                    else
                    {
                        /* we assume the value was validated and thus is within the valid range. */
                        data[bytes_written] = cast(u8)(0xe0 | (codepoint >> 12)); /* 1110xxxx. */
                        bytes_written += 1;
                        data[bytes_written] = cast(u8)(0x80 | ((codepoint >> 6) & 0x3f)); /* 10xxxxxx. */
                        bytes_written += 1;
                        data[bytes_written] = cast(u8)(0x80 | (codepoint & 0x3f)); /* 10xxxxxx. */
                        bytes_written += 1;
                    }
                }

                case #char "\"";
                    data[bytes_written] = #char "\"";
                    bytes_written += 1;
                case #char "\\";
                    data[bytes_written] = #char "\\";
                    bytes_written += 1;
                case #char "/";
                    data[bytes_written] = #char "/";
                    bytes_written += 1;
                case #char "b";
                    data[bytes_written] = 0x08; // "\b" - backspace
                    bytes_written += 1;
                case #char "f";
                    data[bytes_written] = 0x0c; // "\f" - form feed
                    bytes_written += 1;
                case #char "n";
                    data[bytes_written] = #char "\n";
                    bytes_written += 1;
                case #char "r";
                    data[bytes_written] = #char "\r";
                    bytes_written += 1;
                case #char "t";
                    data[bytes_written] = #char "\t";
                    bytes_written += 1;
                case #char "\r";
                    data[bytes_written] = #char "\r";
                    bytes_written += 1;

                    /* check if we have a "\r\n" sequence. */
                    if #char "\n" == src[offset]
                    {
                        data[bytes_written] = #char "\n";
                        bytes_written += 1;
                        offset += 1;
                    }
                case #char "\n";
                    data[bytes_written] = #char "\n";
                    bytes_written += 1;
            }
        }
        else
        {
            /* copy the character. */
            data[bytes_written] = src[offset];
            bytes_written += 1;
            offset += 1;
        }
    }

    /* skip trailing '"' or '\''. */
    offset += 1;
    /* record the size of the string. */
    str.string_size = bytes_written;
    /* add null terminator to string. */
    data[bytes_written] = 0;
    bytes_written += 1;
    /* move data along. */
    state.data += bytes_written;
    /* update offset. */
    state.offset = offset;
}

json_get_array_size :: ( state: *json_parse_state_s ) -> int
{
    flags_bitset := state.flags_bitset;
    elements: u64 = 0;
    allow_comma: int = 0;
    src := state.src;
    size := state.size;

    if #char "[" != src[state.offset]
    {
        /* expected array to begin with leading '['. */
        state.error = .json_parse_error_unknown;
        return 1;
    }

    /* skip leading '['. */
    state.offset += 1;

    state.dom_size += size_of(json_array_s);

    while state.offset < size
    {
        if json_skip_all_skippables( state )
        {
            state.error = .json_parse_error_premature_end_of_buffer;
            return 1;
        }

        if #char "]" == src[state.offset]
        {
            /* skip trailing ']'. */
            state.offset += 1;
            state.dom_size += size_of(json_array_element_s) * elements;
            /* finished the object! */
            return 0;
        }

        /* if we parsed at least once element previously, grok for a comma. */
        if allow_comma
        {
            if #char "," == src[state.offset]
            {
                /* skip comma. */
                state.offset += 1;
                allow_comma = 0;
            }
            else if !(.json_parse_flags_allow_no_commas & flags_bitset)
            {
                state.error = .json_parse_error_expected_comma_or_closing_bracket;
                return 1;
            }

            if .json_parse_flags_allow_trailing_comma & flags_bitset
            {
                allow_comma = 0;
                continue;
            }
            else
            {
                if json_skip_all_skippables( state )
                {
                    state.error = .json_parse_error_premature_end_of_buffer;
                    return 1;
                }
            }
        }

        if json_get_value_size( state, /* is_global_object = */ 0 )
        {
            /* value parsing failed! */
            return 1;
        }

        /* successfully parsed an array element! */
        elements += 1;
        allow_comma = 1;
    }

    /* we consumed the entire input before finding the closing ']' of the array!
    */
    state.error = .json_parse_error_premature_end_of_buffer;
    return 1;
}

json_parse_array :: ( state: *json_parse_state_s, array: *json_array_s )
{
    src := state.src;
    size := state.size;
    elements: u64 = 0;
    allow_comma: int = 0;
    previous: *json_array_element_s = null;

    /* skip leading '['. */
    state.offset += 1;

    json_skip_all_skippables( state );

    /* reset elements. */
    elements = 0;

    while state.offset < size
    {
        element: *json_array_element_s = null;
        value: *json_value_s = null;

        json_skip_all_skippables( state );

        if #char "]" == src[state.offset]
        {
            /* skip trailing ']'. */
            state.offset += 1;
            /* finished the array! */
            break;
        }

        /* if we parsed at least one element previously, grok for a comma. */
        if allow_comma
        {
            if #char "," == src[state.offset]
            {
                /* skip comma. */
                state.offset += 1;
                allow_comma = 0;
                continue;
            }
        }

        element = cast(*json_array_element_s)state.dom;

        state.dom += size_of(json_array_element_s);

        if null == previous
            /* this is our first element, so record it in our array. */
            array.start = element;
        else
            previous.next = element;

        previous = element;

        if .json_parse_flags_allow_location_information & state.flags_bitset
        {
            value_ex: *json_value_ex_s = cast(*json_value_ex_s)state.dom;
            state.dom += size_of(json_value_ex_s);

            value_ex.offset = state.offset;
            value_ex.line_no = state.line_no;
            value_ex.row_no = state.offset - state.line_offset;

            value = *(value_ex.value);
        }
        else
        {
            value = cast(*json_value_s)state.dom;
            state.dom += size_of(json_value_s);
        }

        element.value = value;

        json_parse_value( state, /* is_global_object = */ 0, value );

        /* successfully parsed an array element! */
        elements += 1;
        allow_comma = 1;
    } 

    /* end the linked list. */
    if previous
        previous.next = null;

    if 0 == elements
        array.start = null;

    array.length = elements;
}

json_get_number_size :: ( state: *json_parse_state_s ) -> int
{
    flags_bitset := state.flags_bitset;
    offset := state.offset;
    size := state.size;
    had_leading_digits: int = 0;
    src := state.src;

    state.dom_size += size_of(json_number_s);

    if (.json_parse_flags_allow_hexadecimal_numbers & flags_bitset)
        && (offset + 1 < size) && (#char "0" == src[offset])
        && ((#char "x" == src[offset + 1]) || (#char "X" == src[offset + 1]))
    {
        /* skip the leading 0x that identifies a hexadecimal number. */
        offset += 2;

        /* consume hexadecimal digits. */
        while (offset < size) && ( (#char "0" <= src[offset] && src[offset] <= #char "9")
            || (#char "a" <= src[offset] && src[offset] <= #char "f")
            || (#char "A" <= src[offset] && src[offset] <= #char "F") )
        {
            offset += 1;
        }
    }
    else
    {
        found_sign: int = 0;
        inf_or_nan: int = 0;

        if (offset < size) && ( (#char "-" == src[offset]) || ( (.json_parse_flags_allow_leading_plus_sign & flags_bitset)
            && (#char "+" == src[offset]) ) )
        {
            /* skip valid leading '-' or '+'. */
            offset += 1;
            found_sign = 1;
        }

        if (.json_parse_flags_allow_inf_and_nan & flags_bitset)
        {
            inf := "Infinity";
            nan := "NaN";

            if offset + xx inf.count < size
            {
                found := memcmp( src + offset, inf.data, inf.count ) == 0;

                if found
                {
                    /* We found our special 'Infinity' keyword! */
                    offset += xx inf.count;
                    inf_or_nan = 1;
                }
            }

            if offset + xx nan.count < size
            {
                found := memcmp( src + offset, nan.data, nan.count ) == 0;

                if found
                {
                    /* We found our special 'NaN' keyword! */
                    offset += xx nan.count;
                    inf_or_nan = 1;
                }
            }

            if inf_or_nan
            {
                if offset < size
                {
                    if src[offset] ==
                    {
                        case #char "0"; #through;
                        case #char "1"; #through;
                        case #char "2"; #through;
                        case #char "3"; #through;
                        case #char "4"; #through;
                        case #char "5"; #through;
                        case #char "6"; #through;
                        case #char "7"; #through;
                        case #char "8"; #through;
                        case #char "9"; #through;
                        case #char "e"; #through;
                        case #char "E";
                            /* cannot follow an inf or nan with digits! */
                            state.error = .json_parse_error_invalid_number_format;
                            state.offset = offset;
                            return 1;
                    }
                }
            }
        }

        if found_sign && !inf_or_nan && (offset < size) && !(#char "0" <= src[offset] && src[offset] <= #char "9")
        {
            /* check if we are allowing leading '.'. */
            if !(.json_parse_flags_allow_leading_or_trailing_decimal_point & flags_bitset) || (#char "." != src[offset])
            {
                /* a leading '-' must be immediately followed by any digit! */
                state.error = .json_parse_error_invalid_number_format;
                state.offset = offset;
                return 1;
            }
        }

        if (offset < size) && (#char "0" == src[offset])
        {
            /* skip valid '0'. */
            offset += 1;
            /* we need to record whether we had any leading digits for checks later. */
            had_leading_digits = 1;

            if (offset < size) && (#char "0" <= src[offset] && src[offset] <= #char "9")
            {
                /* a leading '0' must not be immediately followed by any digit! */
                state.error = .json_parse_error_invalid_number_format;
                state.offset = offset;
                return 1;
            }
        }

        /* the main digits of our number next. */
        while (offset < size) && (#char "0" <= src[offset] && src[offset] <= #char "9")
        {
            offset += 1;
            /* we need to record whether we had any leading digits for checks later. */
            had_leading_digits = 1;
        }

        if (offset < size) && (#char "." == src[offset])
        {
            offset += 1;

            if (offset >= size) || !(#char "0" <= src[offset] && src[offset] <= #char "9")
            {
                if !(.json_parse_flags_allow_leading_or_trailing_decimal_point & flags_bitset) || !had_leading_digits
                {
                    /* a decimal point must be followed by at least one digit. */
                    state.error = .json_parse_error_invalid_number_format;
                    state.offset = offset;
                    return 1;
                }
            }

            /* a decimal point can be followed by more digits of course! */
            while (offset < size) && (#char "0" <= src[offset] && src[offset] <= #char "9")
            {
                offset += 1;
            }
        }

        if (offset < size) && (#char "e" == src[offset] || #char "E" == src[offset])
        {
            /* our number has an exponent! Skip 'e' or 'E'. */
            offset += 1;

            if (offset < size) && (#char "-" == src[offset] || #char "+" == src[offset])
            {
                /* skip optional '-' or '+'. */
                offset += 1;
            }

            if (offset < size) && !(#char "0" <= src[offset] && src[offset] <= #char "9")
            {
                /* an exponent must have at least one digit! */
                state.error = .json_parse_error_invalid_number_format;
                state.offset = offset;
                return 1;
            }

            /* consume exponent digits. */
            offset += 1;
            while (offset < size) && (#char "0" <= src[offset] && src[offset] <= #char "9")
                offset += 1;
        }
    }

    if offset < size
    {
        if src[offset] ==
        {
            case #char " "; #through;
            case #char "\t"; #through;
            case #char "\r"; #through;
            case #char "\n"; #through;
            case #char "}"; #through;
            case #char ","; #through;
            case #char "]";
                /* all of the above are ok. */
            case #char "=";
                if !(.json_parse_flags_allow_equals_in_object & flags_bitset)
                {
                    state.error = .json_parse_error_invalid_number_format;
                    state.offset = offset;
                    return 1;
                }
            case;
                state.error = .json_parse_error_invalid_number_format;
                state.offset = offset;
                return 1;
        }
    }

    state.data_size += offset - state.offset;

    /* one more byte for null terminator ending the number string! */
    state.data_size += 1;
    /* update offset. */
    state.offset = offset;

    return 0;
}

json_parse_number :: ( state: *json_parse_state_s, number: *json_number_s )
{
    flags_bitset := state.flags_bitset;
    offset := state.offset;
    size := state.size;
    bytes_written: u64 = 0;
    src := state.src;
    data := state.data;

    number.number = data;

    if .json_parse_flags_allow_hexadecimal_numbers & flags_bitset
    {
        if (#char "0" == src[offset]) && ( (#char "x" == src[offset + 1]) || (#char "X" == src[offset + 1]) )
        {
            /* consume hexadecimal digits. */
            while (offset < size) && ( (#char "0" <= src[offset] && src[offset] <= #char "9")
                || (#char "a" <= src[offset] && src[offset] <= #char "f")
                || (#char "A" <= src[offset] && src[offset] <= #char "F")
                || (#char "x" == src[offset]) || (#char "X" == src[offset]) )
            {
                data[bytes_written] = src[offset];
                bytes_written += 1;
                offset += 1;
            }
        }
    }

    while offset < size
    {
        end := false;

        if src[offset] ==
        {
            case #char "0"; #through;
            case #char "1"; #through;
            case #char "2"; #through;
            case #char "3"; #through;
            case #char "4"; #through;
            case #char "5"; #through;
            case #char "6"; #through;
            case #char "7"; #through;
            case #char "8"; #through;
            case #char "9"; #through;
            case #char "."; #through;
            case #char "e"; #through;
            case #char "E"; #through;
            case #char "+"; #through;
            case #char "-";
                data[bytes_written] = src[offset];
                bytes_written += 1;
                offset += 1;
            case;
                end = true;
        }

        if end
            break;
    }

    if .json_parse_flags_allow_inf_and_nan & flags_bitset
    {
        inf_strlen :: 8; /* = strlen("Infinity");. */
        nan_strlen :: 3; /* = strlen("NaN");. */

        if offset + inf_strlen < size
        {
            if #char "I" == src[offset]
            {
                memcpy( data + bytes_written, src + offset, inf_strlen );
                bytes_written += inf_strlen;
                offset += inf_strlen;
            }
        }

        if offset + nan_strlen < size
        {
            if #char "N" == src[offset]
            {
                memcpy( data + bytes_written, src + offset, nan_strlen );
                bytes_written += nan_strlen;
                offset += nan_strlen;
            }
        }
    }

    /* record the size of the number. */
    number.number_size = bytes_written;
    /* add null terminator to number string. */
    data[bytes_written] = 0;
    bytes_written += 1;
    /* move data along. */
    state.data += bytes_written;
    /* update offset. */
    state.offset = offset;
}

json_skip_all_skippables :: ( state: *json_parse_state_s ) -> int
{
    /* skip all whitespace and other skippables until there are none left. note
    * that the previous version suffered from read past errors should. the
    * stream end on json_skip_c_style_comments eg. '{"a" ' with comments flag.
    */
    did_consume: int = 1;
    size := state.size;

    if .json_parse_flags_allow_c_style_comments & state.flags_bitset
    {
        while 0 != did_consume
        {
            if state.offset == size
            {
                state.error = .json_parse_error_premature_end_of_buffer;
                return 1;
            }

            did_consume = json_skip_whitespace( state );

            /* This should really be checked on access, not in front of every call.
            */
            if state.offset >= size
            {
                state.error = .json_parse_error_premature_end_of_buffer;
                return 1;
            }

            did_consume |= json_skip_c_style_comments( state );
        }
    }
    else
    {
        while 0 != did_consume
        {
            if state.offset == size
            {
                state.error = .json_parse_error_premature_end_of_buffer;
                return 1;
            }

            did_consume = json_skip_whitespace( state );
        }
    }

    if state.offset == size
    {
        state.error = .json_parse_error_premature_end_of_buffer;
        return 1;
    }

    return 0;
}

json_skip_whitespace :: ( state: *json_parse_state_s ) -> int
{
    offset := state.offset;
    size := state.size;
    src := state.src;

    if offset >= state.size
        return 0;

    // TODO This double check is quite silly que no?
    /* the only valid whitespace according to ECMA-404 is ' ', '\n', '\r' and '\t'. */
    if src[offset] ==
    {
        case;
            return 0;
        case #char " ";
        case #char "\r";
        case #char "\t";
        case #char "\n";
    }

    while offset < size
    {
        if src[offset] ==
        {
            case;
                /* Update offset. */
                state.offset = offset;
                return 1;
            case #char " "; #through;
            case #char "\r"; #through;
            case #char "\t";
                /* break; */
            case #char "\n";
                state.line_no += 1;
                state.line_offset = offset;
        }

        offset += 1;
    }

    /* Update offset. */
    state.offset = offset;
    return 1;
}

json_skip_c_style_comments :: ( state: *json_parse_state_s ) -> int
{
    /* to have a C-style comment we need at least 2 characters of space */
    if (state.offset + 2) > state.size
        return 0;

    /* do we have a comment? */
    if #char "/" == state.src[state.offset]
    {
        if #char "/" == state.src[state.offset + 1]
        {
            /* we had a comment of the form // */
            /* skip first '/' */
            state.offset += 1;
            /* skip second '/' */
            state.offset += 1;

            while state.offset < state.size
            {
                if state.src[state.offset] ==
                {
                    case;
                        /* skip the character in the comment */
                        state.offset += 1;
                    case #char "\n";
                        /* if we have a newline, our comment has ended! Skip the newline */
                        state.offset += 1;

                        /* we entered a newline, so move our line info forward */
                        state.line_no += 1;
                        state.line_offset = state.offset;
                        return 1;
                }
            }

            /* we reached the end of the JSON file! */
            return 1;
        }
        else if #char "*" == state.src[state.offset + 1]
        {
            /* we had a comment in the C-style long form */
            /* skip '/' */
            state.offset += 1;
            /* skip '*' */
            state.offset += 1;

            while state.offset + 1 < state.size
            {
                if (#char "*" == state.src[state.offset]) && (#char "/" == state.src[state.offset + 1])
                {
                    /* we reached the end of our comment! */
                    state.offset += 2;
                    return 1;
                }
                else if #char "\n" == state.src[state.offset]
                {
                    /* we entered a newline, so move our line info forward */
                    state.line_no += 1;
                    state.line_offset = state.offset;
                }

                /* skip character within comment */
                state.offset += 1;
            }

            /* comment wasn't ended correctly which is a failure */
            return 1;
        }
    }

    /* we didn't have any comment, which is ok too! */
    return 0;
}


json_hexadecimal_value :: ( c: *u8, size: u64, result: *u32 ) -> int
{
    if size > size_of(u32) * 2
        return 0;

    result.* = 0;
    p := c;
    while xx (p - c) < size
    {
        result.* <<= 4;
        digit := json_hexadecimal_digit( p.* );
        if digit < 0 || digit > 15
            return 0;

        result.* |= xx digit;
        p += 1;
    }
    return 1;
}

json_hexadecimal_digit :: ( c: int ) -> int
{
    if #char "0" <= c && c <= #char "9"
        return c - #char "0";
    if #char "a" <= c && c <= #char "f"
        return c - #char "a" + 10;
    if #char "A" <= c && c <= #char "F"
        return c - #char "A" + 10;

    return -1;
}


json_write_minified_value :: ( value: *json_value_s, builder: *String_Builder ) -> bool
{
    if value.type ==
    {
        case;
            return false;
        case .json_type_number;
            return json_write_number( cast(*json_number_s)value.payload, builder );
        case .json_type_string;
            return json_write_string( cast(*json_string_s)value.payload, builder );
        case .json_type_array;
            return json_write_minified_array( cast(*json_array_s)value.payload, builder );
        case .json_type_object;
            return json_write_minified_object( cast(*json_object_s)value.payload, builder );
        case .json_type_true;
            append( builder, "true" );
        case .json_type_false;
            append( builder, "false" );
        case .json_type_null;
            append( builder, "null" );
    }
    return true;
}

json_write_pretty_value :: ( value: *json_value_s, depth: int, indent: string, newline: string, builder: *String_Builder ) -> bool
{
    if value.type ==
    {
        case;
            return false;
        case .json_type_number;
            return json_write_number( cast(*json_number_s)value.payload, builder );
        case .json_type_string;
            return json_write_string( cast(*json_string_s)value.payload, builder );
        case .json_type_array;
            return json_write_pretty_array( cast(*json_array_s)value.payload, depth, indent, newline, builder );
        case .json_type_object;
            return json_write_pretty_object( cast(*json_object_s)value.payload, depth, indent, newline, builder );
        case .json_type_true;
            append( builder, "true" );
        case .json_type_false;
            append( builder, "false" );
        case .json_type_null;
            append( builder, "null" );
    }
    return true;
}

json_write_number :: ( number: *json_number_s, builder: *String_Builder ) -> bool
{
    if number.number_size >= 2
    {
        if number.number[1] ==
        {
            case #char "x"; #through;
            case #char "X";
                /* The number is a json_parse_flags_allow_hexadecimal_numbers hexadecimal
                * so we have to do extra work to convert it to a non-hexadecimal for JSON
                * output. */
                // TODO Pass flags so we can support writing this as is
                str := string.{ xx number.number_size - 2, number.number + 2 };
                parsed_number := string_to_int( str, 16, u64 );

                print_to_builder( builder, "%", parsed_number );

                return true;
        }
    }

    /* check to see if the number has leading/trailing decimal point. */
    i: u64 = 0;
    /* skip any leading sign char. */
    if (i < number.number_size) && ( (#char "+" == number.number[i]) || (#char "-" == number.number[i]) )
        i += 1;

    num_str := string.{ xx (number.number_size - i), number.number + i };

    /* check if we have nan. */
    nan := "NaN";
    if num_str == nan
    {
        /* NaN becomes 0 because JSON can't support it. */
        append( builder, "0" );
        return true;
    }

    /* if we had a leading '-' we need to record it in the JSON output. */
    if #char "-" == number.number[0]
        append( builder, #char "-" );

    /* check if we have infinity. */
    inf := "Infinity";
    if num_str == inf
    {
        append( builder, "1.7976931348623158e308" );
        return true;
    }

    /* if we had a leading decimal point. */
    if (i < number.number_size) && (#char "." == number.number[i])
        /* insert a '0' to fix the leading decimal point for JSON output. */
        append( builder, "0" );

    /* and output the rest of the number as normal. */
    append( builder, num_str );

    /* if we had a trailing decimal point. */
    if num_str[ num_str.count - 1] == #char "."
        /* insert a '0' to fix the trailing decimal point for JSON output. */
        append( builder, "0" );

    return true;
}

json_write_string :: ( str: *json_string_s, builder: *String_Builder ) -> bool
{
    append( builder, #char "\"" ); /* open the string. */

    for i: 0 .. str.string_size - 1
    {
        if str.str[i] ==
        {
            case #char "\"";
                append( builder, "\\\"" );
            case #char "\\";
                append( builder, "\\\\" );
            case 0x08;
                append( builder, "\\b" );
            case 0x0c;
                append( builder, "\\f" );
            case #char "\n";
                append( builder, "\\n" );
            case #char "\r";
                append( builder, "\\r" );
            case #char "\t";
                append( builder, "\\t" );
            case;
                append( builder, str.str[i] );
        }
    }

    append( builder, #char "\"" ); /* close the string. */
    return true;
}

json_write_minified_array :: ( array: *json_array_s, builder: *String_Builder ) -> bool
{
    append( builder, #char "[" ); /* open the array. */

    element: *json_array_element_s = array.start;
    while( element != null )
    {
        if element != array.start
            append( builder, #char "," ); /* ','s seperate each element. */

        ok := json_write_minified_value( element.value, builder );
        if !ok
            /* value was malformed! */
            return false;

        element = element.next;
    }

    append( builder, #char "]" ); /* close the array. */
    return true;
}

json_write_pretty_array :: ( array: *json_array_s, depth: int, indent: string, newline: string, builder: *String_Builder ) -> bool
{
    append( builder, #char "[" ); /* open the array. */

    if 0 < array.length
    {
        append( builder, newline );

        element: *json_array_element_s = array.start;
        while element != null
        {
            if element != array.start
                print_to_builder( builder, ",%", newline ); /* ','s seperate each element. */

            for k: 0 .. depth
                append( builder, indent );

            ok := json_write_pretty_value( element.value, depth + 1, indent, newline, builder );
            if !ok
                /* value was malformed! */
                return false;

            element = element.next;
        }

        append( builder, newline );

        for k: 0 .. depth - 1
            append( builder, indent );
    }

    append( builder, #char "]" ); /* close the array. */
    return true;
}

json_write_minified_object :: ( object: *json_object_s, builder: *String_Builder ) -> bool
{
    append( builder, #char "{" ); /* open the object. */

    element: *json_object_element_s = object.start;
    while element != null
    {
        if element != object.start
            append( builder, #char "," ); /* ','s seperate each element. */

        ok := json_write_string( element.name, builder );
        if !ok
            /* string was malformed! */
            return false;

        append( builder, #char ":" ); /* ':'s seperate each name/value pair. */

        ok = json_write_minified_value( element.value, builder );
        if !ok
            /* value was malformed! */
            return false;

        element = element.next;
    }

    append( builder, #char "}" ); /* close the object. */
    return true;
}

json_write_pretty_object :: ( object: *json_object_s, depth: int, indent: string, newline: string, builder: *String_Builder ) -> bool
{
    append( builder, #char "{" ); /* open the object. */

    if 0 < object.length
    {
        append( builder, newline );

        element: *json_object_element_s = object.start;
        while element != null
        {
            if element != object.start
                print_to_builder( builder, ",%", newline ); /* ','s seperate each element. */

            for k: 0 .. depth
                append( builder, indent );

            ok := json_write_string( element.name, builder );
            if !ok
                /* string was malformed! */
                return false;

            /* " : "s seperate each name/value pair. */
            append( builder, " : " );

            ok = json_write_pretty_value( element.value, depth + 1, indent, newline, builder );
            if !ok
                /* value was malformed! */
                return false;

            element = element.next;
        }

        append( builder, newline );

        for k: 0 .. depth - 1
            append( builder, indent );
    }

    append( builder, #char "}" ); /* close the object. */
    return true;
}

