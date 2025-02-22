#import "Basic";
#import "Compiler";
#import "System";
#import "String";
#import "Math";
#import "Hash_Table";

Reflector :: #import "reflector";
#import "unotest";

// #load "src/basic.jai";
// #load "src/reflect.jai"; // For StructNodeIdentFor

build :: ()
{
    set_build_options_dc( .{do_output=false} );  // No executable for this workspace.

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
            case "--release"; #through;
            case "-release"; #through;
            case "release";
                build_release = true;
                print( "Building release version.\n" );
        }
    }

    if build_release
    {
        set_optimization( *global_options, .VERY_OPTIMIZED, true );
        global_options.backend =.LLVM;
    }
    else
    {
        set_optimization( *global_options, .DEBUG, true );
        global_options.backend =.X64;
    }


    // Test executable
    {
        w := BeginTestWorkspace( "Tests", global_options );

        // TODO How do we control exactly what to add etc? Also.. rename
        Reflector.AddSourceStubs( w );
        add_build_file( "src/test.jai", w );

        EndTestWorkspace( w );
    }

    // Benchmark executable
    {
        w := compiler_create_workspace( "Bench" );

        options := global_options;
        options.output_type = .EXECUTABLE;
        options.output_executable_name = "bench";
        set_build_options( options, w );

        // compiler_begin_intercept( w );

        Reflector.AddSourceStubs( w );
        add_build_file( "src/bench.jai", w );

        // MessageLoop( w );

        // compiler_end_intercept(w);
    }

}
#run build();


#if 1
{

#scope_file

// TODO TODO If we can live with just reporting the location of the enclosing struct declaration for errors (like we're currently doing)
// I dont think most of this crap is needed
// Test everything out with this removed..

EmitStructCodeNodes :: false;
PrintDebugLogs :: false;


#if 0
{
    TryEmitNodeFor :: ( st: *Type_Info_Struct, w: Workspace ) -> bool
    {
        // Do we have it yet
        node, nodeFound := table_find( *globalStructNodes, st );
        if nodeFound
        {
            // TODO Seems like we dont even need the placeholder!
            // Add a placeholder with a unique name for this Type_Info pointer
            // The relevant Reflect() function will know to look for it
            //str := tprint( "#placeholder _struct_node_%;\n", st );
            //add_build_string( str, w ); //, code = REFLECT_MODULE_SCOPE );

            str := tprint( "% :: cast(*Code_Struct) 0x%;\n", StructNodeIdentFor( st, false ), node );
            add_build_string( str, w ); //, code = REFLECT_MODULE_SCOPE );

            // Also add it to the list to emit them all at the end as an array
            array_add( *globalNodesTable, node );

            #if PrintDebugLogs
            {
                print( "##### Emitted node for %\n", st.name );
            }

            return true;
        }
        return false;
    }
}

MessageLoop :: ( w: Workspace, verboseTests := false )
{
    while true
    {
        message := compiler_wait_for_message();
        if message.kind ==
        {
        case .FILE;
            file := cast(*Message_File) message;
            // Pretty janky
            // Why oh why can't you refer to specific placeholders by name when calling add_build_string!?
            if file.fully_pathed_filename == tprint( "%src/test.jai", #filepath )
                globalMainTestFile = file;

        case .TYPECHECKED;
            typechecked := cast(*Message_Typechecked) message;
            #if PrintDebugLogs
            {
                print( "# Got msg TYPECHECKED (% things: % headers, % bodies, % structs)\n", typechecked.all.count,
                       typechecked.procedure_headers.count, typechecked.procedure_bodies.count, typechecked.structs.count );
            }

            for tc: typechecked.procedure_headers
            {
                proc := tc.expression;

                // Skip procs that are imported from somewhere
                if proc.enclosing_load && proc.enclosing_load.enclosing_import {
                    if proc.enclosing_load.enclosing_import.module_type != .MAIN_PROGRAM
                        continue;
                }

                // If it is a procedure we want to test, make note of it for later.
                if HasNote( proc, "test" )
                {
                    array_add( *globalTests, proc );
                }
                if HasNote( proc, "test_buildtime" )
                {
                    array_add( *globalBuildTests, proc );
                }
            }

            #if EmitStructCodeNodes
            {
                // Add the code node of each struct to a table
                for tc: typechecked.structs
                {
                    stNode := cast(*Code_Struct) tc.expression;
                    if stNode.defined_type.name
                        table_set( *globalStructNodes, stNode.defined_type, stNode );
                }

                for tc: typechecked.procedure_headers
                {
                    header := tc.expression;

                    // If it is a procedure we want to run, make note of it for later.
                    args: string;
                    if HasNote( header, "runAfterTypechecking", *args )
                    {
                        array_add( *globalRunners, header );
                        array_add( *globalRunnerArgs, args );
                    }

                    // Examine all Reflect() calls and make a note of the type of the first argument
                    // If it's a pointer to some struct, emit its Code_Struct node pointer as a program constant
                    if header.name == "Reflect"
                        && header.arguments.count == 2 && header.arguments[0].type_inst.pointer_to != null
                    {
                        inst := header.arguments[0].type_inst.pointer_to;
                        if inst.result.type == .STRUCT
                        {
                            st := cast(*Type_Info_Struct) inst.result;

                            emitted, newlyAdded := find_or_add( *globalReflectedTypes, st );
                            if newlyAdded && !<<emitted
                            {
                                #if PrintDebugLogs
                                {
                                    print( "##### Found Reflect for type %\n", st.name );
                                }

                                // If we have not yet emitted a node for this type, try to do so right away (if we have it)
                                if TryEmitNodeFor( st, w )
                                {
                                    <<emitted = true;
                                }
                            }
                        }
                    }
                }
            }

        case .PHASE;
            phase := cast(*Message_Phase) message;
            if phase.phase ==
            {
                case .ALL_SOURCE_CODE_PARSED;
                {
                    #if PrintDebugLogs
                    {
                        print( "# Got msg ALL_SOURCE_CODE_PARSED\n" );
                    }
                }
                case .TYPECHECKED_ALL_WE_CAN;
                {
                    #if PrintDebugLogs
                    {
                        print( "# Got msg TYPECHECKED_ALL_WE_CAN (% waiting)\n", phase.num_items_waiting_to_typecheck );
                    }

                    // Emit all tests we've found until now
                    if !globalEmittedTestsTable
                    {
                        // Emit all struct nodes as a constant array
                        print_to_builder( *globalBuilder, "AllTests: [%] TestCase = .[\n", globalTests.count );

                        for globalTests
                            print_to_builder( *globalBuilder, "    .{ name = \"%\", proc = % },\n", it.name, it.name );

                        append( *globalBuilder, "];\n" );

                        add_build_string( builder_to_string( *globalBuilder ), w, message = globalMainTestFile );
                        free_buffers( *globalBuilder );
                        array_reset( *globalTests );

                        globalEmittedTestsTable = true;
                    }

                    if !globalEmittedBuildTests
                    {
                        print_to_builder( *globalBuilder, "AllBuildtimeTests: [%] TestCase = .[\n", globalBuildTests.count );

                        for globalBuildTests
                        print_to_builder( *globalBuilder, "    .{ name = \"%\", proc = % },\n", it.name, it.name );

                        append( *globalBuilder, "];\n" );

                        add_build_string( builder_to_string( *globalBuilder ), w, message = globalMainTestFile );
                        free_buffers( *globalBuilder );
                        array_reset( *globalBuildTests );

                        globalEmittedBuildTests = true;
                    }
                    else if !ranEmittedBuildTests
                    {
                        // NOTE Need this to be stallable because we have tests depending on the output of other tests
                        print_to_builder( *globalBuilder, "#run,stallable RunAllBuildtimeTests( % );\n", verboseTests );
                        add_build_string( builder_to_string( *globalBuilder ), w, message = globalMainTestFile );
                        free_buffers( *globalBuilder );

                        ranEmittedBuildTests = true;
                    }

                    #if EmitStructCodeNodes
                    {
                        // Continue trying to emit any nodes we haven't yet emitted
                        for globalReflectedTypes
                        {
                            // Key, value
                            st, emitted := it_index, it;
                            if !emitted
                            {
                                if TryEmitNodeFor( st, w )
                                    table_set( *globalReflectedTypes, st, true );
                                else if phase.num_items_waiting_to_typecheck == 0
                                    // If we got to typecheck everything, and we still couldn't emit a node for some type, we failed
                                    assert( false, "Didn't typecheck node for type '%' in time to emit it", st.name );
                            }
                        }

                        // NOTE When there's nothing else to typecheck, assume we have all the nodes (and no others will be added)
                        // and emit a table containing all of them, plus run any runners
                        if phase.num_items_waiting_to_typecheck == 0 && !globalEmittedNodesTable
                        {
                            // Emit all struct nodes as a constant array
                            print_to_builder( *globalBuilder, "globalReflectedStructNodes: [%] *Code_Struct: .[\n", globalNodesTable.count );

                            for globalNodesTable
                            {
                                print_to_builder( *globalBuilder, "    cast(*Code_Struct) 0x%,\n", it );
                            }

                            append( *globalBuilder, "];\n" );

                            // Then emit a run directive for each of our runners
                            for globalRunners
                            {
                                // Pass any arguments to the note verbatim
                                print_to_builder( *globalBuilder, "#run %(%);", it.name, globalRunnerArgs[it_index] );
                            }

                            add_build_string( builder_to_string( *globalBuilder ), w ); //, code = REFLECT_MODULE_SCOPE );
                            free_buffers( *globalBuilder );

                            globalEmittedNodesTable = true;
                        }
                    }
                }
                case .PRE_WRITE_EXECUTABLE;
                {
                    // TODO Any diagnostic / info msgs should go here so as to not interfere with the compiler's own msgs
                    #if PrintDebugLogs
                    {
                        print( "# Got msg PRE_WRITE_EXECUTABLE\n" );
                    }
                }
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

HasNote :: ( header: *Code_Procedure_Header, note: string, args: *string = null ) -> bool
{
    for header.notes
    {
        if it.text == note
            return true;
        // Crappy check to also account for notes followed by "arguments"
        else if starts_with( it.text, tprint( "%(", note ) )
        {
            if args
            {
                // Anything in parenthesis is considered arguments to the note
                s := slice( it.text, note.count, it.text.count - note.count );
                if s && s[0] == #char "(" && s[s.count - 1] == #char ")"
                {
                    <<args = slice( s, 1, s.count - 2 );
                }
            }
            return true;
        }
    }
    return false;
}


globalBuilder: String_Builder;
globalStructNodes: Table(*Type_Info_Struct, *Code_Struct);
globalReflectedTypes: Table(*Type_Info_Struct, bool);
globalNodesTable: [..] *Code_Struct;
globalEmittedNodesTable: bool = false;

globalRunners: [..] *Code_Procedure_Header;
globalRunnerArgs: [..] string;

}

globalMainTestFile: *Message;
globalTests: [..] *Code_Procedure_Header;
globalBuildTests: [..] *Code_Procedure_Header;
globalEmittedTestsTable: bool = false;
globalEmittedBuildTests: bool = false;
ranEmittedBuildTests: bool = false;
