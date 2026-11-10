FUNCTION_BLOCK FB_ConfirmedStop
VAR_INPUT
    EncoderFeedbackProven : BOOL;
    SpeedFresh : BOOL;
    StatusFresh : BOOL;
    DriveReportsStopped : BOOL;
    MeasuredRPM : REAL;
    CycleSec : REAL;
    ThresholdRPM : REAL;
    StableSec : REAL;
END_VAR
VAR_OUTPUT
    Confirmed : BOOL;
END_VAR
VAR
    StableForSec : REAL;
END_VAR

IF EncoderFeedbackProven AND SpeedFresh AND StatusFresh
   AND DriveReportsStopped
   AND (ABS(MeasuredRPM) <= ThresholdRPM)
   AND (StableSec > 0.0) THEN
    StableForSec := MIN(StableSec, StableForSec + CycleSec);
ELSE
    StableForSec := 0.0;
END_IF;
Confirmed := StableForSec >= StableSec AND StableSec > 0.0;
END_FUNCTION_BLOCK
