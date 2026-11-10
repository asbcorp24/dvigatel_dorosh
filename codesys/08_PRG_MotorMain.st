PROGRAM PRG_MotorMain
VAR
    // Set PLC_PRG task period to 20 ms and verify actual runtime.
    CycleSec : REAL := 0.02;
    TemperatureWarningC : REAL := 0.0; // configure from motor documentation
    TemperatureTripC : REAL := 0.0;
    TemperatureResetC : REAL := 0.0;
    TemperatureLimitsConfigured : BOOL := FALSE;
    MaximumRPM : REAL := 0.0; // set only after mechanical review
    MaximumHz : REAL := 0.0;
    MotorPolePairs : UINT := 0; // expected 2 for 4 poles, verify
    MaxStopWaitSec : REAL := 30.0;

    // These inputs require proven wiring and runtime diagnostics.
    DriveReportsStopped : BOOL := FALSE;
    DriveStatusDecoded : BOOL := FALSE;
    DriveSpeedScalingProven : BOOL := FALSE;
    DriveSpeedSignedRPM : REAL := 0.0;
    DriveResponseAgeSec : REAL := 10000.0;

    Temp : FB_Pt100Protection;
    HB : FB_Heartbeat;
    StopCheck : FB_ConfirmedStop;
    Motion : FB_MotorMotion;
    DriveCmd : FB_DriveCommand;

    Cmd : ST_MotorCommand;
    CmdPulse : BOOL;
    LastRequestID : WORD;
    RequestID : WORD;
    RequestDir : INT;
    ValidRequest : BOOL;
    Interlocks : BOOL;
    RunPermitted : BOOL;
    SpeedFresh : BOOL;
    StatusFresh : BOOL;
    TelemetryState : UINT;
    SignedX10 : DINT;
    SignedX10DW : DWORD;
    Ack : BOOL := FALSE; // safety reset must be engineered separately
END_VAR

// Inputs Holding[0..4] must be protected against concurrent partial writes.
// The application accepts ONLY a changed command ID and validated fields.
// For production replace this elementary transaction handling with a
// verified command buffer / consistency token / single writer.
RequestID := GVL_PC.Holding[4];
RequestDir := 0;
IF GVL_PC.Holding[2] = 1 THEN RequestDir := 1; END_IF;
IF GVL_PC.Holding[2] = 2 THEN RequestDir := -1; END_IF;

Cmd.SpeedRPM := WORD_TO_REAL(GVL_PC.Holding[0]) / 10.0;
Cmd.RampSec := WORD_TO_REAL(GVL_PC.Holding[1]) / 10.0;
Cmd.Direction := RequestDir;
Cmd.Sequence := RequestID;
ValidRequest := RequestDir <> 0
    AND Cmd.SpeedRPM >= 0.0 AND Cmd.SpeedRPM <= MaximumRPM
    AND Cmd.RampSec >= 0.1 AND Cmd.RampSec <= 600.0;

CmdPulse := (RequestID <> LastRequestID) AND ValidRequest;
IF RequestID <> LastRequestID THEN LastRequestID := RequestID; END_IF;

Temp(TemperatureC:=GVL_PC.Pt100TemperatureC,
    ChannelHealthy:=GVL_PC.Pt100InputValid,
    WarningC:=TemperatureWarningC, TripC:=TemperatureTripC,
    ResetBelowC:=TemperatureResetC, Ack:=FALSE,
    LimitsConfigured:=TemperatureLimitsConfigured);
HB(Counter:=GVL_PC.Holding[3], Enable:=GVL_PC.CommissionEnable,
   CycleSec:=CycleSec, TimeoutSec:=2.0);

// Freshness: true pulse must be generated on an actual successful RTU response.
IF GVL_DriveIO.DriveReadFresh THEN
    DriveResponseAgeSec := 0.0;
ELSE
    DriveResponseAgeSec := MIN(10000.0, DriveResponseAgeSec + CycleSec);
END_IF;
SpeedFresh := DriveResponseAgeSec < 0.6 AND DriveSpeedScalingProven
              AND GVL_PC.PGFeedbackProven;
StatusFresh := DriveResponseAgeSec < 0.6 AND DriveStatusDecoded;
StopCheck(EncoderFeedbackProven:=GVL_PC.PGFeedbackProven,
    SpeedFresh:=SpeedFresh, StatusFresh:=StatusFresh,
    DriveReportsStopped:=DriveReportsStopped,
    MeasuredRPM:=DriveSpeedSignedRPM, CycleSec:=CycleSec,
    ThresholdRPM:=5.0, StableSec:=0.4);

RunPermitted := GVL_PC.CommissionEnable AND GVL_PC.ConfigValid
    AND GVL_PC.HardwareSafetyOK AND Temp.Permit AND HB.Active
    AND SpeedFresh AND StatusFresh AND NOT GVL_DriveIO.DriveFault;

Interlocks := RunPermitted;
Motion(Enable:=GVL_PC.CommissionEnable AND GVL_PC.ConfigValid,
    InterlocksOK:=Interlocks,
    CommandPulse:=CmdPulse AND HB.Active, Command:=Cmd,
    FaultAck:=FALSE, StopConfirmed:=StopCheck.Confirmed,
    CycleSec:=CycleSec, MaxRPM:=MaximumRPM,
    StopTimeoutSec:=MaxStopWaitSec);
DriveCmd(ProfileRPM:=Motion.ProfileRPM,
    RunRequest:=Motion.RunRequest,
    ReverseRequest:=Motion.ReverseRequest,
    StopRequest:=Motion.StopRequest,
    MotorPolePairs:=MotorPolePairs, MaximumHz:=MaximumHz,
    ConfigurationValid:=GVL_PC.ConfigValid);

// NOT connected to Modbus write requests by default.
// Once RTU scheduler is implemented, it must send frequency and control
// sequentially, verify each acknowledgement, and latch failures.
GVL_DriveIO.PendingFrequencyWord := DriveCmd.FrequencyWord;
GVL_DriveIO.PendingControlWord := DriveCmd.ControlWord;

CASE Motion.State OF
 MOTOR_DISABLED: TelemetryState := 0;
 MOTOR_IDLE: TelemetryState := 1;
 MOTOR_RAMP: TelemetryState := 2;
 MOTOR_WAIT_STOP: TelemetryState := 3;
 MOTOR_RUN: TelemetryState := 4;
 MOTOR_FAULT: TelemetryState := 90;
END_CASE;

GVL_PC.Holding[100] := Motion.AcceptedSequence;
GVL_PC.Holding[101] := UINT_TO_WORD(TelemetryState);
SignedX10 := REAL_TO_DINT(DriveSpeedSignedRPM * 10.0);
SignedX10DW := DINT_TO_DWORD(SignedX10);
GVL_PC.Holding[102] := DWORD_TO_WORD(SHR(SignedX10DW,16));
GVL_PC.Holding[103] := DWORD_TO_WORD(SignedX10DW AND 16#0000FFFF);
IF GVL_PC.Pt100InputValid THEN
 GVL_PC.Holding[104] := INT_TO_WORD(REAL_TO_INT(GVL_PC.Pt100TemperatureC*10.0));
ELSE
 GVL_PC.Holding[104] := 16#7FFF;
END_IF;
GVL_PC.Holding[105] := GVL_DriveIO.FrequencyRaw;
GVL_PC.Holding[106] := GVL_DriveIO.CurrentRaw;
GVL_PC.Holding[107] := GVL_DriveIO.StatusRaw;
GVL_PC.Holding[108] := GVL_DriveIO.FaultCodeRaw;
GVL_PC.Holding[109] := BOOL_TO_WORD(SpeedFresh AND StatusFresh);
GVL_PC.Holding[110] := BOOL_TO_WORD(GVL_PC.PGFeedbackProven);
GVL_PC.Holding[111] := BOOL_TO_WORD(Temp.Permit);
GVL_PC.Holding[112] := BOOL_TO_WORD(StopCheck.Confirmed);
GVL_PC.Holding[113] := DriveCmd.FrequencyWord;
GVL_PC.Holding[114] := DriveCmd.ControlWord;
GVL_PC.Holding[115] := GVL_DriveIO.SpeedRaw;
GVL_PC.Holding[116] := BOOL_TO_WORD(RunPermitted);
END_PROGRAM
