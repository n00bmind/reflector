
#scope_module

#import "Print_Color";

TestCase :: struct
{
    name: string;
    proc: #type ();

    msgBuffer: = String_Builder.{ allocator = temp };
    failedExpr: string;
    failedLocation: Source_Code_Location;
    failed: bool = false;
}
#add_context testCase: *TestCase;

// Returns how many tests fails from the given list failed
RunTests :: ( tests: [] TestCase, verbose: bool ) -> s32
{
    failedCount: s32 = 0;

    if verbose
        context.log_level = .VERBOSE;

    for t: tests
    {
        PrintAndIndent( "Running %...", t.name );

        newContext := context;
        newContext.testCase = *t;
        newContext.logger = TestMsgLogger;
        push_context newContext
        {
            t.proc();
        }

        if t.failed
        {
            print_color( "FAILED!\n", color = .RED );
            failedCount += 1;
        }
        else
        {
            print_color( "OK.\n", color = .GREEN );
        }

        if t.msgBuffer.initialized && context.log_level >= .VERBOSE
        {
            // TODO Can this be a bit less contrast still?
            log( builder_to_string( *t.msgBuffer ), flags = .VERBOSE_ONLY );
        }

        if t.failed
            // TODO Want to also log this (but not print the line twice!)
            print_color( "%: Expression '%' evaluated as false.\n", t.failedLocation, t.failedExpr, color = .HI_WHITE );

        reset_temporary_storage();
    }

    // TODO Summary

    return failedCount;
}

PrintAndIndent :: ( fmt: string, args: ..Any )
{
    msg := tprint( fmt, ..args );
    // TODO Want to also log this (but not print the line twice!)
    print_color( msg, color = .HI_WHITE );

    Spaces16 :: "                ";
    IndentCol :: 70;

    num_spaces := IndentCol - msg.count;
    if num_spaces <= 0
        return;

    div := num_spaces / 16;
    mod := num_spaces % 16;

    for 1..div
        write_string( Spaces16 );

    s := Spaces16;
    s.count = mod;
    write_string( s );
}

TestMsgLogger :: ( msg: string, data: *void, info: Log_Info )
{
    assert( context.testCase != null );
    append( *context.testCase.msgBuffer, msg );
}

