#import "Basic";
#import "Compiler";
#import "System";
#import "String";
#import "Math";
#import "Hash_Table";

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
            print( "# Got msg TYPECHECKED (% things: % headers, % bodies, % structs)\n", typechecked.all.count,
                   typechecked.procedure_headers.count, typechecked.procedure_bodies.count, typechecked.structs.count );

            // Add the code node of each struct to a list
            // FIXME Do this the other way around: Add code nodes to a hashtable indexed by their defined_type
            // Then as soon as procedure headers come in we can emit both the placeholder and its definition
            // TODO Compare compile times before & after!
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
                if HasNote( header, "runForReflectedStructs" )
                {
                    assert( runForReflectedStructs == null, "Should have only a single procedure marked with '@runForReflectedStructs'" );
                    runForReflectedStructs = header;
                }

                // Examine all Reflect() calls and make a note of the type of the first argument
                if header.name == "Reflect"
                    && header.arguments.count == 2 && header.arguments[0].type_inst.pointer_to != null
                {
                    inst := header.arguments[0].type_inst.pointer_to;
                    if inst.result.type == .STRUCT
                    {
                        st := cast(*Type_Info_Struct) inst.result;
                        v, newlyAdded := find_or_add( *globalReflectedStructs, st );
                        if newlyAdded
                        {
                            print( "##### Found Reflect for type %\n", st.name );
                            // Set value to false when adding a new type to indicate we haven't emitted the node for it yet
                            <<v = false;

                            // TODO Seems like we dont even need the placeholder!
                            // Add a placeholder with a unique name for this Type_Info pointer
                            // The relevant Reflect() function will know to look for it
                            //str := tprint( "#placeholder _struct_node_%;\n", st );
                            //add_build_string( str, message.workspace ); //, code = REFLECT_MODULE_SCOPE );
                        }
                    }
                }
            }


        case .PHASE;
            phase := cast(*Message_Phase) message;
            if phase.phase ==
            {
                case .ALL_SOURCE_CODE_PARSED;
                    print( "# Got msg ALL_SOURCE_CODE_PARSED\n" );
                case .TYPECHECKED_ALL_WE_CAN;
                {
                    print( "# Got msg TYPECHECKED_ALL_WE_CAN (% waiting)\n", phase.num_items_waiting_to_typecheck );

                    // Need to emit these as soon as they come in ..
                    for globalStructNodes
                    {
                        v := table_find_pointer( *globalReflectedStructs, it.defined_type );
                        // Exists and has not yet been emmited..
                        if v != null && !<<v
                        {
                            print( "##### Emit node for %\n", it.defined_type.name );

                            str := tprint( "_struct_node_%:: cast(*Code_Struct) 0x%;\n", it.defined_type, it );
                            add_build_string( str, message.workspace ); //, code = REFLECT_MODULE_SCOPE );
                            // Set table entry to true to indicate we have emitted this type
                            <<v = true;
                        }
                    }


                    #if 0
                    {
                        if phase.num_items_waiting_to_typecheck == 0 && !globalEmittedNodesTable
                        {
                            print_to_builder( *globalBuilder, "globalReflectedStructNodes: [%] *Code_Struct: .[\n", globalReflectedStructs.count );

                            for globalStructNodes
                            {
                                v := table_find_pointer( *globalReflectedStructs, it.defined_type );
                                // Exists and has not yet been emmited..
                                if v != null && !<<v
                                {
                                    print( "##### Emit node for %\n", it.defined_type.name );

                                    print_to_builder( *globalBuilder, "    cast(*Code_Struct) 0x%,\n", it );
                                    // Set table entry to true to indicate we have emitted this type
                                    <<v = true;
                                }
                            }

                            append( *globalBuilder, "];\n" );
                            add_build_string( builder_to_string( *globalBuilder ), message.workspace ); //, code = REFLECT_MODULE_SCOPE );

                            free_buffers( *globalBuilder );

                            globalEmittedNodesTable = true;
                        }
                    }
                }
                case .PRE_WRITE_EXECUTABLE;
                    print( "# Got msg PRE_WRITE_EXECUTABLE\n" );
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


globalBuilder: String_Builder;
globalStructNodes: [..] *Code_Struct;
globalReflectedStructs: Table(*Type_Info_Struct, bool);
globalEmittedNodesTable: bool = false;

runForReflectedStructs: *Code_Procedure_Header;
