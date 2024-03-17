#import "Basic";
#import "Compiler";
#import "System";
#import "String";
#import "Math";

#load "src/basic.jai";

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
    compiler_begin_intercept( w );

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

    MessageLoop( w );

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

            // Add the code node of each struct to a list
            for tc: typechecked.structs
            {
                stNode := cast(*Code_Struct) tc.expression;
                if stNode.defined_type.name
                    array_add( *globalStructNodes, stNode );
            }

            for tc: typechecked.procedure_headers
            {
                header := tc.expression;

                // If it is a procedure we want to run, make note of it for later.
                if HasNote( header, "runWithStructNodes" )
                    array_add( *globalProceduresToRun, header );

                // Examine all Reflect() calls and make a note of the type of the first argument
                if header.name == "Reflect"
                    && header.arguments.count == 2 && header.arguments[0].type_inst.pointer_to != null
                {
                    inst := header.arguments[0].type_inst.pointer_to;
                    if inst.result.type == .STRUCT
                    {
                        st := cast(*Type_Info_Struct) inst.result;
                        //print( "###### Reflect called with arg %\n", st.name );
                        array_add( *globalReflectedStructs, st );
                    }
                }
            }


        case .PHASE;
            phase := cast(*Message_Phase) message;
            if phase.phase ==
            {
                case .TYPECHECKED_ALL_WE_CAN;
                    // For each procedure we want to run, generate a #run directive and add that string to the target program.
                    for p: globalProceduresToRun
                    {
                        for globalStructNodes
                        {
                            if Contains( globalReflectedStructs, it.defined_type )
                            {
                                s := tprint( "#run %( cast(*Code_Struct) 0x% );", p.name, it );
                                add_build_string( s, message.workspace );
                            }
                        }
                    }

                    // Reset the arrays so we don't emit duplicate runs for these procedures next time we get a TYPECHECKED_ALL_WE_CAN.
                    array_reset( *globalStructNodes );

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

HasNote :: (header: *Code_Procedure_Header, note: string) -> bool {
    for header.notes  if it.text == note  return true;
    return false;
}


globalStructNodes: [..] *Code_Struct;
// FIXME Should be a set
globalReflectedStructs: [..] *Type_Info_Struct;
globalProceduresToRun: [..] *Code_Procedure_Header;
