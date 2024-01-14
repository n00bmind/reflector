#import "Basic";
#import "Compiler";
#import "System";
#import "String";
#import "Math";

build :: ()
{
    set_build_options_dc( .{do_output=false} );  // No executable for this workspace.

    // The compiler will set the CWD to the directory containing the current file
    //path := get_working_directory();
    //print( "Working directory for 'build' metaprogram: '%'\n", path );

    global_options := get_build_options();
    global_options.output_path = "bin";
    global_options.intermediate_path = "bin";


    build_release := false;
    args := global_options.compile_time_command_line;

    // NOTE These arguments have to be specified last, after any arguments for the compiler itself, separated with a hyphen, e.g:
    // jai build.jai - release
    for arg: args
    {
        if arg ==
        {
          case "release";
            build_release = true;
            print( "Building release version.\n" );
        }
    }


    w := compiler_create_workspace();
    // I assume this must happen before we add files to the compilation?
    compiler_begin_intercept( w, .SKIP_EXPRESSIONS_WITHOUT_NOTES );

    // Main executable
    {
        options := global_options;
        options.output_type = .EXECUTABLE;
        options.output_executable_name = "test";
        if build_release
        {
            set_optimization( *options, .VERY_OPTIMIZED, true );
            options.backend =.LLVM;
        }
        else
        {
            set_optimization( *options, .DEBUG, true );
            options.backend =.X64;
        }
        set_build_options( options, w );

        add_build_file( "src/test.jai", w );
    }

    //MessageLoop( w );

    compiler_end_intercept(w);
}
#run build();


#scope_file

MessageLoop :: ( w: Workspace )
{
    while true
    {
        message := compiler_wait_for_message();
        if message.kind ==
        {
        case .TYPECHECKED;
            typechecked := cast(*Message_Typechecked) message;

            // Look for any struct that we may want to reflect
            for tc: typechecked.structs
            {
                header := tc.expression;
                if HasNote(header, "reflect")
                    array_add(*globalStructsToBuild, header);
            }

        case .PHASE;
            phase := cast(*Message_Phase) message;
            if phase.phase ==
            {
            case .TYPECHECKED_ALL_WE_CAN;
                if !globalAddedBasicStrings
                {
                    add_build_string( reflectPrimitivesFunc, w );
                    globalAddedBasicStrings = true;
                }

                // For each struct we're interested in, generate its Reflect() overload
                for globalStructsToBuild
                {
                    print( "--> Generating reflection code for struct '%'\n", it.defined_type.name );

                    st := cast(*Type_Info_Struct)it.defined_type;
                    codeString := GenReflectFunction( st, w );

                    add_build_string( codeString, w );
                }

                // Reset the array so we don't emit duplicate code for these structs next time we get this message
                array_reset(*globalStructsToBuild);

            case .PRE_WRITE_EXECUTABLE;
                // TODO Any diagnostic / info msgs should go here so as to not interfere with the compiler's own msgs
            }

        case .COMPLETE;
            break;
        }
    }
}

HasNote :: (header: *Code_Struct, note: string) -> bool {
    for header.notes  if it.text == note  return true;
    return false;
}

// NOTE Returns a temporary array
// TODO Polymorph and extract to bricks
GetNoteArgs :: ( type: Type_Info_Struct_Member, name: string ) -> noteFound: bool, args: []string
{
    for type.notes
    {
        if starts_with( it, name )
        {
            // Does it have any arguments
            if it.count > name.count && it[name.count] == #char "("
            {
                // TODO Improve reporting of malformed arg expressions
                // Get substring up until closing parens
                argsFound, argString, _ := split_from_left( slice( it, name.count + 1, it.count ), #char ")" );
                if !argsFound
                    return false, .[];

                // Parse args as comma separated strings
                // Weird cast required to get the 'fast' single char overload
                // New 'context arguments' make it look even prettier
                args := split( argString, cast(u8) #char ",",, allocator = temp );
                return true, args;
            }
            else
                return true, .[];
        }
    }
    return false, .[];
}

GenReflectFunction :: ( st: *Type_Info_Struct, w: Workspace, body_only: bool = false ) -> string
{
    defer free_buffers( *globalBuilder );

    append( *globalBuilder, tprint( "Reflect :: ( d: *%, r: *Reflector ) -> ReflectResult\n", st.name ) );
    append( *globalBuilder, "{\n" );
    append( *globalBuilder, "    info: ReflectedTypeInfo;\n" );
    append( *globalBuilder, tprint( "    BeginReflectType( *info, %, r );\n", st.name ) );
    append( *globalBuilder, "    defer EndReflectType( *info, r );\n" );
    append( *globalBuilder, "    \n" );

    // TODO Skip constants, usings, procedures? etc
    // TODO TODO Check discovered layout against a persisted one from last compilation
    // FIXME We'd need the code node of each member for more accurate location reporting in compiler_report
    // TODO When writing, *always order by offset in the source struct type* for cache friendliness
    // TODO When reading, the stream tells us the order of members to write to, but assume memory order too
    for m: st.members
    {
        // Parse field id
        idFound, idArgs := GetNoteArgs( m, "id" );
        if !idFound
            // This guy is not serialised
            continue;

        if !idArgs
        {
            compiler_report( "'id' note requires a u16 argument (in parenthesis)", compiler_get_struct_location( w, st ) );
            return "";
        }
        else if idArgs.count > 1
        {
            // TODO Show "some args ignored" warning
        }

        // NOTE string_to_int does not currently check for overflows if a small type is specified
        fieldId, idOk, _ := string_to_int( idArgs[0], 10 );
        if !idOk
        {
            compiler_report( "Unable to parse field 'id' argument into a u16", compiler_get_struct_location( w, st ) );
            return "";
        }
        else if fieldId > U16_MAX
        {
            compiler_report( "Field 'id' argument is too big", compiler_get_struct_location( w, st ) );
            return "";
        }

        // TODO Parse optional name attribute (& more..)

        print( "+%. %: % (%)  '%'\n", m.offset_in_bytes, m.name, type_to_string( m.type ), m.type.runtime_size, m.notes );
        append( *globalBuilder, tprint( "    ReflectField( *d.%, %, \"%\", *info, r );\n", m.name, fieldId, m.name ) );
    }

    // TODO Test that this correctly returns any errors set in EndReflectType
    append(*globalBuilder, "    return r.error;\n");
    append(*globalBuilder, "}\n");

    return builder_to_string( *globalBuilder );
}

// The general Reflect() overload for all primitive types. Accept anything that's not a struct.
// NOTE This needs to be inserted from the metaprogram too! (any way we could *not* have to do that?)
reflectPrimitivesFunc := #string ENDSTR
Reflect :: inline ( d: *$T, r: *Reflector ) -> ReflectResult
#modify
{
    ti := cast(*Type_Info) T;
    return ti.type != .STRUCT;
}
{
    #if r.IsReading
        return ReflectOk;
    else
        return ReflectResult.SomeError;
}
ENDSTR


// TODO Threading?
globalStructsToBuild: [..] *Code_Struct;
globalBuilder: String_Builder;
globalAddedBasicStrings: bool = false;
