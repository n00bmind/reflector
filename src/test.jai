// TODO Add an example test case similar to what codeape does, which touches on a lot of the use cases:
// - Serialises in the metaprogram
// - Deserialises in the target program
// - Uses a custom Reflect() overload

#import "Basic";
#import "Compiler";
Print :: #import "Program_Print";
// TODO We're inserting code that now requires the user to import stuff.. how do we deal with this?
#import "Bucket_Array";

// TODO Remove dependencies!
#import "bricks";
#import "reflector";


// Test files
#load "tests/monster.jai";


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


#scope_file

TestCase :: struct
{
    name: string;
    proc: #type ();

    failedExpr: string;
    failedLocation: Source_Code_Location;
    failed: bool = false;
}
#add_context testCase: *TestCase;

#placeholder AllTests; // [] TestCase


RunAllTests :: () -> s32
{
    failedCount: s32 = 0;

    for t: AllTests
    {
        log( "Running %...", t.name );

        newContext := context;
        newContext.testCase = *t;
        push_context newContext
        {
            t.proc();
        }

        // TODO Custom logger withouth NLs, terminal colors
        if t.failed
        {
            log( "FAILED!\n" );
            log( "%: Expression '%' evaluated as false.\n", t.failedLocation, t.failedExpr );
            failedCount += 1;
        }
        else
            log( "OK.\n" );
    }

    return failedCount;
}
