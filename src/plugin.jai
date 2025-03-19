
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
AddUserStrings :: ( w: Workspace )
{
    add_build_string( ReflectorStrings, w );
    add_build_string( BinaryReflectorStrings, w );
    add_build_string( BinaryReflectorGMStrings, w );
    add_build_string( BinaryReflectorFBStrings, w );
    add_build_string( JsonReflectorStrings, w );
}


#scope_file

DebugLogs :: true;
VerboseLogs :: false;

globalReflectedTypes: Table(*Type_Info_Struct, bool);


OnAddSource :: ( p: *Metaprogram_Plugin )
{
    AddUserStrings( p.workspace );
}

// TODO Since we've already inserted the polymorphic Reflect() for structs above,
// it doesnt seem like we're gonna need to do any manual parsing of stuff?
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

            // TODO We need to only be triggered by actual function invocations, and also not emit code when a user-defined body exists
            for tc: typechecked.procedure_bodies
            {
                body := tc.expression;

                for tc.subexpressions
                {
                    if it.kind == .PROCEDURE_CALL
                    {
                        call := cast(*Code_Procedure_Call) it;
                        if call.procedure_expression.kind == .IDENT
                        {
                            ident := cast(*Code_Ident) call.procedure_expression;
                            if ident.name == "Reflect"
                            {
                                //
                            }
                        }
                    }
                }
            }


            for tc: typechecked.procedure_headers
            {
                header := tc.expression;
                #if 1
                {
                    // Examine all Reflect() calls and make a note of the type of the first argument
                    // If it's a pointer to some struct, emit the corresponding procedure body into the target workspace
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
                                #if DebugLogs
                                {
                                    print( "##### Found Reflect() call for type %\n", st.name );
                                }

                                // If we have not yet emitted a procedure body for this type, try to do so now
                                if TryEmitBodyFor( st, p.workspace )
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

TryEmitBodyFor :: ( st: *Type_Info_Struct, w: Workspace ) -> bool
{
    return true;
}

