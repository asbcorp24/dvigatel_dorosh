FUNCTION_BLOCK FB_Heartbeat
VAR_INPUT
    Counter : WORD;
    Enable : BOOL;
    CycleSec : REAL;
    TimeoutSec : REAL;
END_VAR
VAR_OUTPUT
    Active : BOOL;
END_VAR
VAR
    Previous : WORD;
    AgeSec : REAL := 10000.0;
    Initialized : BOOL;
END_VAR

IF NOT Enable THEN
    Active := FALSE;
    Initialized := FALSE;
    AgeSec := TimeoutSec;
ELSE
    IF NOT Initialized THEN
        Previous := Counter;
        Initialized := TRUE;
        AgeSec := TimeoutSec;
    ELSIF Counter <> Previous THEN
        Previous := Counter;
        AgeSec := 0.0;
    ELSE
        AgeSec := MIN(10000.0, AgeSec + CycleSec);
    END_IF;
    Active := AgeSec < TimeoutSec;
END_IF;
END_FUNCTION_BLOCK
