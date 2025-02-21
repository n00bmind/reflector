// TODO Add an example test case similar to what codeape does, which touches on a lot of the use cases:
// - Serialises in the metaprogram
// - Deserialises in the target program
// - Uses a custom Reflect() overload

#import "Basic";
#import "Compiler";
// NOTE We need to namespace this, otherwise our 'get_plugin()' proc causes an "identical overloads" error..
// TODO Can we scope our get_plugin() proc?
Print :: #import "Program_Print";
// TODO We're inserting code that now requires the user to import stuff.. how do we deal with this?
#import "Bucket_Array";
#import "Command_Line";

// TODO Remove dependencies!
#import "bricks";
#import "reflector";



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

#load "test_utils.jai";

// Test files
#load "tests/monster.jai";
#load "tests/nested.jai";
#load "tests/buildtime.jai";

#placeholder AllTests; // [] TestCase
#placeholder AllBuildtimeTests; // [] TestCase


RunAllTests :: () -> s32
{
    Arguments :: struct
    {
        verbose: bool;
    }
    parsedOk, args, is_set := parse_arguments( Arguments );
    verbose := parsedOk && is_set.verbose;

    failedCount := RunTests( AllTests, verbose );
    return failedCount;
}

RunAllBuildtimeTests :: ( verbose: bool ) -> s32 #compile_time
{
    failedCount := RunTests( AllBuildtimeTests, verbose );
    print( "\n" );
    return failedCount;
}

