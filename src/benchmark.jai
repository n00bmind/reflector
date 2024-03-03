// TODO Extract to a module (& bricks)
// TODO Windows & x64 only for now
#import "Machine_X64";

//// Inspired by https://github.com/cmuratori/computer_enhance/blob/main/perfaware/part3/listing_0103_repetition_tester.cpp

// NOTE Implement these in your own tests
// Initialise a test. You can prepare your own userdata using the given pointer so each iteration can access it
SetUpFunc       :: #type ( userdata: **void ) -> bool;
// This is the actual thing. Use the available API on the passed bench instance to record times etc.
BenchmarkFunc   :: #type ( tester: *RepetitionTester, userdata: *void );
// Optional: verify data results after a stable time has been reached and produce a hash
VerifyFunc      :: #type ( userdata: *void, checksum_out: *u64 );
// Shutdown test. Remember to free any memory / resources in your custom userdata
TearDownFunc    :: #type ( userdata: *void );


RepetitionTester :: struct
{
    MaxMsgCount :: 32;
    MaxMsgSize :: 128;

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
        totalBytes:         u64;
        maxTicks:          u64;
        maxTicksByteCount: u64;
        minTicks:          u64 = U64_MAX;
        minTicksByteCount: u64;
        testCount:          u32;
    }

    results:                  Results;
    userdata:                 *void;
    cpuFrequency:             u64;
    curProcessedBytes:        u64;
    targetProcessedBytes:     u64;
    curAccumulatedTicks:     u64;
    lastMinMeasuredTimestamp: u64;
    timeToStabiliseSecs:      s32;
    openBlockCount:           s32;
    closedBlockCount:         s32;
    state:                    State;
}

// When running multiple waves in a comparison test (without calling Reset() in between tests), the CPU frequency will be re-estimated to ensure it hasnt changed.
// Same for the target byte count each wave should reach, when provided.
NewTestWave :: ( using tester: *RepetitionTester, targetProcessedByteCount: u64 = 0, tryForSeconds: s32 = 10 )
{
    assert( tester.state != .Running, "Don't call Start on a running benchmark" );

    if state == .Unitialized
    {
        // TODO Does this work with non-zero defaults?
        <<tester = .{};
        cpuFrequency = EstimateCPUFrequency();
        targetProcessedBytes = targetProcessedByteCount;
    }
    else if state == .Completed || state == .Error
    {
        if cpuFrequency != EstimateCPUFrequency()
        {
            Error( tester, "CPU frequency changed" );
            return;
        }
        if targetProcessedByteCount != targetProcessedBytes
        {
            Error( tester, "Target processed bytes changed" );
            return;
        }
    }

    tester.state = .Running;
    // TODO This is premultiplied by the freq in Casey's code
    tester.timeToStabiliseSecs = tryForSeconds;
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

CountBytes :: ( using tester: *RepetitionTester, byteCount: u64 )
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
    if stillRunning && TicksToSeconds( now - lastMinMeasuredTimestamp, tester.cpuFrequency ) > xx timeToStabiliseSecs
    {
        state = .Completed;
        LogResults( tester );
    }

    return stillRunning;
}

#scope_file

QueryPerformanceFrequency :: (result: *s64) -> s32 #foreign kernel32;
QueryPerformanceCounter   :: (result: *s64) -> s32 #foreign kernel32;

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

TicksToSeconds :: ( ticks: u64, cpuFrequency: u64 ) -> float64
{
    result: float64;

    if cpuFrequency != 0
        result = cast(float64)ticks / cpuFrequency;
    
    return result;
}

ComputeBandwidth :: ( ticks: u64, cpuFrequency: u64, byteCount: u64 ) -> float64
{
    seconds := TicksToSeconds( ticks, cpuFrequency );
    bandwidth := byteCount / (seconds * Gigabytes);

    return bandwidth;
}

LogTime :: ( using tester: *RepetitionTester, label: string, ticks: u64, byteCount: u64 )
{
    seconds := TicksToSeconds( ticks, tester.cpuFrequency );
    log( "%: % (%ms.)", label, ticks, seconds * 1000 );

    if byteCount
    {
        // TODO Should be sameline. Can we log without a newline?
        bandwidth := ComputeBandwidth( ticks, tester.cpuFrequency, byteCount );
        log( " %Gb/s", bandwidth );
    }
}

LogResults :: ( using tester: *RepetitionTester )
{
    log( "_____ results _____" );
    LogTime( tester, "Min", results.minTicks, results.minTicksByteCount );
    LogTime( tester, "Max", results.maxTicks, results.maxTicksByteCount );
    if results.testCount
        LogTime( tester, "Avg", results.totalTicks / results.testCount, results.totalBytes / results.testCount );
    log( "Ran % test cycles", results.testCount );
}

Error :: ( using tester: *RepetitionTester, fmt: string, args: ..Any )
{
    // FIXME How do we preserve formatting here? What's the right way to do this in Jai?
    log_error( tprint( "Error: %", fmt ), ..args );
    state = .Error;
}

