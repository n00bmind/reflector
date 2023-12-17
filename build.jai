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
    // TODO Will this still have everything in the typechecked list of structs below?
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
                    codeString := GenReflectFunction( st );

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

GenReflectFunction :: ( st: *Type_Info_Struct ) -> string
{
    defer free_buffers( *globalBuilder );

    append( *globalBuilder, tprint( "Reflect :: ( d: *%, r: *Reflector ) -> ReflectResult {\n", st.name ) );

    for m: st.members
    {
        print( "+%. %: % (%)  '%'\n", m.offset_in_bytes, m.name, type_to_string( m.type ), m.type.runtime_size, m.notes );
        append( *globalBuilder, tprint( "    ReflectField( *d.%, r );\n", m.name ) );
    }
                    // TODO 
                    // https://github.com/Ivo-Balbaert/The_Way_to_Jai/blob/main/book/26C_Applications%20of%20Metaprogramming.md#2616-creating-code-for-each-member-in-a-structure
                    //s := tprint("#run %();", it.name);
                    //add_build_string(s, message.workspace);

    append(*globalBuilder, "}\n");

    // TODO Where is added_build_strings.jai?
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
