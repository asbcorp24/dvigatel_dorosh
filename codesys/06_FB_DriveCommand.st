FUNCTION_BLOCK FB_DriveCommand
VAR_INPUT
    ProfileRPM : REAL;
    RunRequest : BOOL;
    ReverseRequest : BOOL;
    StopRequest : BOOL;
    MotorPolePairs : UINT;
    MaximumHz : REAL;
    ConfigurationValid : BOOL;
END_VAR
VAR_OUTPUT
    FrequencyHz : REAL;
    FrequencyWord : WORD;
    ControlWord : WORD;
    Valid : BOOL;
END_VAR

// Feedforward only: true shaft RPM is read from drive.
// This formula does NOT correct asynchronous slip.
Valid := ConfigurationValid AND (MotorPolePairs > 0)
         AND (MaximumHz > 0.0) AND (MaximumHz <= 300.0);
IF NOT Valid THEN
    FrequencyHz := 0.0;
    FrequencyWord := 0;
    ControlWord := 16#0004; // nominal deceleration-stop candidate; verify at bench
ELSE
    FrequencyHz := LIMIT(0.0,
         ABS(ProfileRPM) * UINT_TO_REAL(MotorPolePairs) / 60.0,
         MaximumHz);
    FrequencyWord := REAL_TO_WORD(FrequencyHz * 100.0);
    IF StopRequest OR NOT RunRequest THEN
        ControlWord := 16#0004;
    ELSIF ReverseRequest THEN
        ControlWord := 16#0003;
    ELSE
        ControlWord := 16#0001;
    END_IF;
END_IF;
END_FUNCTION_BLOCK
