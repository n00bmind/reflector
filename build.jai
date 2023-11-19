#import "Basic";
#import "Compiler";
#import "System";
#import "String";

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
    // TODO Will this still have everything in the typechecked list of structs below?
    compiler_begin_intercept( w, .SKIP_EXPRESSIONS_WITHOUT_NOTES );

    // Main executable
    {
        options := global_options;
        options.output_type = .EXECUTABLE;
        options.output_executable_name = "test";
        if build_release
            set_optimization( *options, .VERY_OPTIMIZED, true );
        else
            set_optimization( *options, .VERY_DEBUG, true );
        set_build_options( options, w );

        add_build_file( "src/test.jai", w );
    }

    message_loop();

    compiler_end_intercept(w);
}
#run build();


message_loop :: ()
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
                if has_note(header, "serialized")
                    array_add(*structs_to_build, header);
            }
            
          case .PHASE;
            phase := cast(*Message_Phase) message;
            if phase.phase == .TYPECHECKED_ALL_WE_CAN
            {
                // For each struct we're interested in, generate its reflection code
                for structs_to_build
                {
                    print( "Found struct %\n", it.defined_type.name );
                    // TODO 
                    //s := tprint("#run %();", it.name);
                    //add_build_string(s, message.workspace);
                }

                // Reset the array so we don't emit duplicate code for these structs
                // next time we get a TYPECHECKED_ALL_WE_CAN.
                array_reset(*structs_to_build);
            }
            
          case .COMPLETE;
            break;
        }
    }
}

has_note :: (header: *Code_Struct, note: string) -> bool {
    for header.notes  if it.text == note  return true;
    return false;
}

structs_to_build: [..] *Code_Struct;
