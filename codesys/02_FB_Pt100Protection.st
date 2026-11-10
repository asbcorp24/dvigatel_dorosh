FUNCTION_BLOCK FB_Pt100Protection
VAR_INPUT
    TemperatureC : REAL;
    ChannelHealthy : BOOL;
    WarningC : REAL;
    TripC : REAL;
    ResetBelowC : REAL;
    Ack : BOOL;
    LimitsConfigured : BOOL;
END_VAR
VAR_OUTPUT
    Warning : BOOL;
    TripLatched : BOOL;
    Valid : BOOL;
    Permit : BOOL;
END_VAR

Valid := ChannelHealthy AND LimitsConfigured
         AND (ResetBelowC < WarningC)
         AND (WarningC < TripC);
Warning := Valid AND (TemperatureC >= WarningC);

IF (NOT Valid) OR (TemperatureC >= TripC) THEN
    TripLatched := TRUE;
END_IF;

// Acknowledgement alone cannot clear fault if input is missing.
IF Ack AND Valid AND (TemperatureC <= ResetBelowC) THEN
    TripLatched := FALSE;
END_IF;
Permit := Valid AND NOT TripLatched;
END_FUNCTION_BLOCK
