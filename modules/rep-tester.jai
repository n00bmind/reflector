#import "Basic";
// TODO Windows & x64 only for now
#import "Machine_X64";

//// Inspired by https://github.com/cmuratori/computer_enhance/blob/main/perfaware/part3/listing_0103_repetition_tester.cpp

RepetitionTester :: struct
{
    MaxMsgCount :: 32;
    MaxMsgSize :: 128;
    U64_MAX :u64:   0xffff_ffff_ffff_ffff;

    State :: enum
    {
        Unitialized;
        Running;
        Completed;
        Error;
    }

    Results :: struct
    {
        totalTicks:        u64;
        totalBytes:        s64;
        maxTicks:          u64;
        maxTicksByteCount: s64;
        minTicks:          u64 = U64_MAX;
        minTicksByteCount: s64;
        testCount:         s32;
    }

    results:                  Results;
    userdata:                 *void;
    ticksPerSecond:           u64;
    curProcessedBytes:        s64;
    targetProcessedBytes:     s64;
    curAccumulatedTicks:      u64;
    lastMinMeasuredTimestamp: u64;
    timeToStabiliseTicks:     u64;
    openBlockCount:           s32;
    closedBlockCount:         s32;
    state:                    State;
}

// When running multiple waves in a comparison test (without calling Reset() in between tests), the CPU frequency will be re-estimated to ensure it hasnt changed.
// Same for the target byte count each wave should reach, when provided.
NewTestWave :: ( using tester: *RepetitionTester, targetProcessedByteCount: s64 = 0, tryForSeconds: int = 10 )
{
    assert( tester.state != .Running, "Don't call NewTestWave on a running benchmark" );
    assert( tryForSeconds > 0, "Need a positive value for tryForSeconds" );

    if state == .Unitialized
    {
        <<tester = .{};
        ticksPerSecond = EstimateCPUFrequency();
        targetProcessedBytes = targetProcessedByteCount;
    }
    else if state == .Completed || state == .Error
    {
        newFreq := EstimateCPUFrequency();
        if ticksPerSecond != newFreq
        {
            Error( tester, "CPU frequency changed (was %, is %)", ticksPerSecond, newFreq );
            return;
        }
        if targetProcessedByteCount != targetProcessedBytes
        {
            Error( tester, "Target processed bytes changed (was %, is %)", targetProcessedBytes, targetProcessedByteCount );
            return;
        }
    }

    tester.state = .Running;
    tester.timeToStabiliseTicks = cast(u64)tryForSeconds * ticksPerSecond;
    tester.lastMinMeasuredTimestamp = rdtsc();
}

// Treat next test on this tester as independent with regards to previous waves
Reset :: ( using tester: *RepetitionTester )
{
    state = .Unitialized;
}

BeginTime :: ( using tester: *RepetitionTester )
{
    openBlockCount += 1;
    curAccumulatedTicks -= rdtsc();
}

EndTime :: ( using tester: *RepetitionTester )
{
    closedBlockCount += 1;
    curAccumulatedTicks += rdtsc();
}

CountBytes :: ( using tester: *RepetitionTester, byteCount: s64 )
{
    curProcessedBytes += byteCount;
}

IsRunning :: ( using tester: *RepetitionTester ) -> bool
{
    return state == .Running;
}

BeginTestCycle :: ( using tester: *RepetitionTester ) -> bool
{
    if !IsRunning( tester )
        return false;

    now := rdtsc();

    if openBlockCount > 0
    {
        if openBlockCount != closedBlockCount
            Error( tester, "Unbalanced BeginTime/EndTime blocks" );

        if targetProcessedBytes != 0 && curProcessedBytes != targetProcessedBytes
            Error( tester, "Processed byte count mismatch" );

        if IsRunning( tester )
        {
            results.testCount += 1;
            results.totalTicks += curAccumulatedTicks;

            if results.maxTicks < curAccumulatedTicks
            {
                results.maxTicks = curAccumulatedTicks;
                results.maxTicksByteCount = curProcessedBytes;
            }

            if results.minTicks > curAccumulatedTicks
            {
                results.minTicks = curAccumulatedTicks;
                results.minTicksByteCount = curProcessedBytes;

                // Whenever we get a new minimum time, reset the clock to the full trial time
                lastMinMeasuredTimestamp = now;
                LogTime( tester, "Min", results.minTicks, results.minTicksByteCount );
            }

            openBlockCount       = 0;
            closedBlockCount     = 0;
            curAccumulatedTicks = 0;
            curProcessedBytes    = 0;
        }
    }

    stillRunning := IsRunning( tester );
    if stillRunning && now - lastMinMeasuredTimestamp > timeToStabiliseTicks
    {
        state = .Completed;
        LogResults( tester );
    }

    return stillRunning;
}


//// Test helpers

// NOTE Implement these in your own tests
// Initialise a test. You can prepare your own userdata using the given pointer so each iteration can access it
SetUpFunc       :: #type ( userdata: **void ) -> bool;
// This is the actual thing. Use the available API on the passed bench instance to record times etc.
BenchmarkFunc   :: #type ( tester: *RepetitionTester, userdata: *void );
// Optional: verify data results after a stable time has been reached and produce a hash
VerifyFunc      :: #type ( userdata: *void, checksum_out: *u64 );
// Shutdown test. Remember to free any memory / resources in your custom userdata
TearDownFunc    :: #type ( userdata: *void );



#scope_file

QueryPerformanceFrequency :: (result: *s64) -> s32 #foreign kernel32;
QueryPerformanceCounter   :: (result: *s64) -> s32 #foreign kernel32;

// Estimate ticks per second using an OS provided wall clock
EstimateCPUFrequency :: () -> u64
{
    waitMillis :: 100;

    wallStart, wallEnd, wallElapsed, wallFreq: s64;
    QueryPerformanceFrequency( *wallFreq );

    ticksStart := rdtsc();
    QueryPerformanceCounter( *wallStart );

    wallWaitTime := wallFreq * waitMillis / 1000;
    while wallElapsed < wallWaitTime
    {
        QueryPerformanceCounter( *wallEnd );
        wallElapsed = wallEnd - wallStart;
    }

    ticksElapsed := rdtsc() - ticksStart;

    result: u64 = 0;
    if wallElapsed != 0
        result = cast(u64)wallFreq * ticksElapsed / cast(u64)wallElapsed;

    return result;
}

TicksToSeconds :: ( ticks: u64, ticksPerSecond: u64 ) -> float64
{
    result: float64;

    if ticksPerSecond != 0
        result = cast(float64)ticks / ticksPerSecond;
    
    return result;
}

ComputeBandwidth :: ( ticks: u64, ticksPerSecond: u64, byteCount: s64 ) -> float64
{
    Gigabytes :: 1024 * 1024 * 1024;

    seconds := TicksToSeconds( ticks, ticksPerSecond );
    bandwidth := byteCount / (seconds * Gigabytes);

    return bandwidth;
}

LogTime :: ( using tester: *RepetitionTester, label: string, ticks: u64, byteCount: s64 )
{
    builder: String_Builder;
    builder.allocator = temp;

    seconds := TicksToSeconds( ticks, tester.ticksPerSecond );
    print_to_builder( *builder, "%: % ticks (%ms.)", label, ticks, seconds * 1000 );

    if byteCount
    {
        bandwidth := ComputeBandwidth( ticks, tester.ticksPerSecond, byteCount );
        print_to_builder( *builder, " -> %Gb/s", bandwidth );
    }

    s := builder_to_string( *builder,, allocator = temp );
    log( s );
}

LogResults :: ( using tester: *RepetitionTester )
{
    log( "_____ results _____" );
    LogTime( tester, "Min", results.minTicks, results.minTicksByteCount );
    LogTime( tester, "Max", results.maxTicks, results.maxTicksByteCount );
    if results.testCount > 0
        LogTime( tester, "Avg", results.totalTicks / xx results.testCount, results.totalBytes / results.testCount );
    log( "Ran % test cycles", results.testCount );
}

Error :: ( using tester: *RepetitionTester, fmt: string, args: ..Any )
{
    log_error( tprint( "Error: %", fmt ), ..args );
    state = .Error;
}


