// TODO Add an example test case similar to what codeape does, which touches on a lot of the use cases:
// - Serialises in the metaprogram
// - Deserialises in the target program
// - Uses a custom Reflect() overload

#import "Basic";
#import "Compiler";
// NOTE We need to namespace this, otherwise our 'get_plugin()' proc causes an "identical overloads" error..
// TODO Can we scope our get_plugin() proc?
Print :: #import "Program_Print";
#import "Print_Color";
// TODO We're inserting code that now requires the user to import stuff.. how do we deal with this?
#import "Bucket_Array";
#import "Command_Line";

// TODO Remove dependencies!
#import "bricks";
#import "reflector";


// Test files
#load "tests/monster.jai";
#load "tests/nested.jai";


main :: ()
{
    exitCode := RunAllTests();

    exit( exitCode );
}


#scope_module

Expect :: ( $expr: Code, loc := #caller_location ) #expand
{
    result: bool = #insert expr;

    if !result
    {
        exprString : string : #insert -> string
        {
            nodes := compiler_get_nodes( expr );

            builder: String_Builder;
            print_to_builder( *builder, "\"" );
            Print.print_expression( *builder, nodes );
            print_to_builder( *builder, "\";" );

            return builder_to_string(*builder);
        };
        context.testCase.failedExpr = exprString;
        context.testCase.failedLocation = loc;
        context.testCase.failed = true;
        `return;
    }
}

TestMsgLogger :: ( msg: string, data: *void, info: Log_Info )
{
    assert( context.testCase != null );
    append( *context.testCase.msgBuffer, msg );
}


#scope_file

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

#placeholder AllTests; // [] TestCase


RunAllTests :: () -> s32
{
    failedCount: s32 = 0;

    Arguments :: struct
    {
        verbose: bool;
    }
    parsedOk, args, is_set := parse_arguments( Arguments );

    if parsedOk && is_set.verbose
        context.log_level = .VERBOSE;

    for t: AllTests
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
            print_color("OK.\n", color = .GREEN);
        }

        // TODO Greyed out colorrr, but still log!
        if t.msgBuffer.initialized && context.log_level >= .VERBOSE
        {
            // log( builder_to_string( *t.msgBuffer ), flags = .VERBOSE_ONLY );
            print_color( builder_to_string( *t.msgBuffer ), color = .HI_BLACK );
        }

        if t.failed
            log_error( "%: Expression '%' evaluated as false.\n", t.failedLocation, t.failedExpr );

        // TODO Clear temp memory
    }

    // TODO Summary

    return failedCount;
}

PrintAndIndent :: ( fmt: string, args: ..Any )
{
    msg := tprint( fmt, ..args );
    // TODO Should prolly leave the boldness for the summary!
    // print_color( msg, color = .HI_WHITE, style = .BOLD );
    print_color( msg, color = .WHITE );

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

