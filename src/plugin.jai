
get_plugin :: () -> *Metaprogram_Plugin
{
    // We are making this on the heap so you could have more than one instance of this plugin running.
    p := New( Metaprogram_Plugin );

    // You don't have to provide all of these hooks. You can leave them null
    // and they just won't be called.
    // p.before_intercept  = before_intercept;
    p.add_source        = OnAddSource;
    // p.message           = OnMessage;
    // p.finish            = finish;
    // p.shutdown          = shutdown;
    // p.handle_one_option = handle_one_option;
    // p.log_help          = log_help;

    return p;
}

// NOTE Some features (custom overloads, custom reflectors) require that the predefined Reflect() overloads in this module
// get inserted into the user's application scope, otherwise our module won't find their code because there's currently no
// mechanism for an app and a module to share scopes.. This is unnecessary for users that don't use these features, but for
// simplicity currently we do it regardless. We try to keep these strings to strictly the minimum necessary, so hopefully
// this won't be a big deal (may have to re-evaluate as we go).
// NOTE This is callable from user programs, to inject the same code that the plugin would inject when invoked from the cmdline
// TODO Check if there's some other "official" way of applying a plugin from a user metaprogram
AddAllStrings :: ( w: Workspace )
{
    add_build_string( ReflectorStrings, w );
    add_build_string( BinaryReflectorStrings, w );
    add_build_string( BinaryReflectorGMStrings, w );
    add_build_string( BinaryReflectorFBStrings, w );
    add_build_string( JsonReflectorStrings, w );
}


#scope_file

#import "Hash_Table";
#import "Compiler";

DebugLogs :: false;
VerboseLogs :: false;

globalInsertedReflectors: Table(*Type_Info_Struct, bool);


OnAddSource :: ( p: *Metaprogram_Plugin )
{
    AddAllStrings( p.workspace );
}

// TODO Besides flat-out inserting all necessary code into the user app namespace, we'd like to also provide a smarter
// mechanism that auto-detects when this is actually required, i.e. when the user app contains a custom Reflect() overload
// or Reflector subtype.
OnMessage :: ( p: *Metaprogram_Plugin, message: *Message )
{
    if message.kind ==
    {
        case .TYPECHECKED;
            typechecked := cast(*Message_Typechecked) message;
            #if DebugLogs && VerboseLogs
            {
                print( "# Got msg TYPECHECKED (% things: % headers, % bodies, % structs)\n", typechecked.all.count,
                typechecked.procedure_headers.count, typechecked.procedure_bodies.count, typechecked.structs.count );
            }

            for tc: typechecked.procedure_headers
            {
                header := tc.expression;
                #if 1
                {
                    // Examine all Reflect() calls and make a note of the type of the first argument
                    // If it's a pointer to some struct, insert the code for the corresponding Reflector
                    if header.name == "Reflect" && header.arguments.count == 2
                        && header.arguments[0].type_inst.pointer_to != null
                        && header.arguments[1].type_inst.pointer_to != null
                    {
                        inst := header.arguments[1].type_inst.pointer_to;
                        if inst.result.type == .STRUCT
                        {
                            st := cast(*Type_Info_Struct) inst.result;

                            inserted, newlyAdded := find_or_add( *globalInsertedReflectors, st );
                            if newlyAdded && !inserted.*
                            {
                                #if DebugLogs
                                {
                                    print( "##### Found Reflect() call for Reflector %\n", st.name );
                                }

                                // If we have not yet inserted the code for this Reflector, do so now
                                if AddCodeFor( st, p.workspace )
                                {
                                    inserted.* = true;
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
                    #if DebugLogs && VerboseLogs
                    {
                        print( "# Got msg ALL_SOURCE_CODE_PARSED\n" );
                    }
                case .TYPECHECKED_ALL_WE_CAN;
                    #if DebugLogs && VerboseLogs
                    {
                        print( "# Got msg TYPECHECKED_ALL_WE_CAN (% waiting)\n", phase.num_items_waiting_to_typecheck );
                    }
                case .PRE_WRITE_EXECUTABLE;
                    // TODO Any diagnostic / info msgs should go here so as to not interfere with the compiler's own msgs
                    #if DebugLogs && VerboseLogs
                    {
                        print( "# Got msg PRE_WRITE_EXECUTABLE\n" );
                    }
            }
        
        case .COMPLETE;
            #if DebugLogs && VerboseLogs
            {
                print( "# Got msg COMPLETE\n" );
            }
    }
}

AddCodeFor :: ( st: *Type_Info_Struct, w: Workspace ) -> bool
{
    return true;
}

