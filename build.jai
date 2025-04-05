#import "Basic";
#import "Compiler";
#import "System";
#import "File";
#import "File_Utilities";
#import "String";
#import "Math";
#import "Hash_Table";

#import "unotest";
#load "module.jai";


build :: ()
{
    set_build_options_dc( .{do_output=false} );  // No executable for this workspace.

    global_options := get_build_options();
    global_options.output_path = "bin";
    global_options.intermediate_path = "bin";

    build_release := false;
    args := global_options.compile_time_command_line;

    BuildMode :: enum
    {
        App;
        Dist;
    }
    buildMode := BuildMode.App;

    // NOTE These arguments have to be specified last, after any arguments for the compiler itself, separated with a hyphen, e.g:
    // jai build.jai - -release
    for arg: args
    {
        if arg ==
        {
            case "--release"; #through;
            case "-release";
                build_release = true;
                print( "Building release version.\n" );

            case "dist";
                buildMode = .Dist;
        }
    }

    if buildMode ==
    {
        case .App;
        {
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

                AddAllStrings( w );
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

                AddAllStrings( w );
                add_build_file( "src/bench.jai", w );
            }
        }
        case .Dist;
        {
            distPath := tprint( "%/dist", global_options.output_path );
            make_directory_if_it_does_not_exist( distPath );

            distFiles := string.[
                "module.jai",
                "src/plugin.jai",
                "src/reflect.jai",
                "src/reflect_binary.jai",
                "src/reflect_binary_gm.jai",
                "src/reflect_binary_fb.jai",
                "src/reflect_json.jai",
                "src/datatypes.jai",
                "src/basic.jai",
            ];

            success := true;
            for f: distFiles
            {
                tgtPath := tprint( "%/%", distPath, f );
                tgtDir := path_strip_filename( tgtPath );
                make_directory_if_it_does_not_exist( tgtDir );

                // print( "Copying % to %..\n", f, tgtPath );
                if !copy_file( f, tgtPath )
                    success = false;
            }

            // Grab current system version of required modules and include it in our own private modules/ folder
            modFiles := string.[
                "unotest.jai",
                "rep-tester.jai",
                "json.jai",
            ];

            _, curDir := get_basename_and_path( #location().fully_pathed_filename );
            for f: modFiles
            {
                for imp: global_options.import_path
                {
                    if begins_with( imp, curDir )
                        continue;

                    srcPath := tprint( "%/%", imp, f );
                    tgtPath := tprint( "modules/%", f );
                    if file_exists( srcPath )
                    {
                        // print( "Copying % to %..\n", srcPath, tgtPath );
                        if !copy_file( srcPath, tgtPath )
                            success = false;
                        break;
                    }
                }
            }

            if !success
                print( "Dist script finished with errors!\n" );
        }
    }
}
#run build();

