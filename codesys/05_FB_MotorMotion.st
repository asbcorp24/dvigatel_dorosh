FUNCTION_BLOCK FB_MotorMotion
VAR_INPUT
    Enable : BOOL;
    InterlocksOK : BOOL;
    CommandPulse : BOOL;
    Command : ST_MotorCommand;
    FaultAck : BOOL;
    StopConfirmed : BOOL;
    CycleSec : REAL;
    MaxRPM : REAL;
    StopTimeoutSec : REAL;
END_VAR
VAR_OUTPUT
    State : E_MotorState := MOTOR_DISABLED;
    ProfileRPM : REAL;             // signed reference
    RunRequest : BOOL;
    ReverseRequest : BOOL;
    StopRequest : BOOL := TRUE;
    FaultLatched : BOOL;
    AcceptedSequence : WORD;
END_VAR
VAR
    Goal : REAL;
    StageStart : REAL;
    StageEnd : REAL;
    StageSec : REAL;
    StageAge : REAL;
    StopAge : REAL;
    PendingReverse : BOOL;
    HeldDirection : INT := 1;
    NewGoal : BOOL;
    ValidCmd : BOOL;
END_VAR

// Device safety must NOT depend on a functioning serial link.
// This output requests a controlled stop; hardware safety is separate.
IF NOT Enable THEN
    State := MOTOR_DISABLED;
    ProfileRPM := 0.0;
    Goal := 0.0;
    PendingReverse := FALSE;
ELSIF NOT InterlocksOK THEN
    FaultLatched := TRUE;
    State := MOTOR_FAULT;
END_IF;

IF State = MOTOR_FAULT THEN
    // Explicit acknowledgement while truly stopped. Does not re-launch.
    IF FaultAck AND InterlocksOK AND StopConfirmed
       AND (Command.SpeedRPM = 0.0) AND NOT CommandPulse THEN
        FaultLatched := FALSE;
        State := MOTOR_IDLE;
        ProfileRPM := 0.0;
        Goal := 0.0;
    END_IF;
ELSIF State = MOTOR_DISABLED THEN
    // Moving from disabled to idle does not accept any pre-existing command.
    IF Enable AND InterlocksOK AND StopConfirmed THEN
        State := MOTOR_IDLE;
    END_IF;
ELSIF Enable AND InterlocksOK THEN
    ValidCmd := (Command.Direction = 1 OR Command.Direction = -1)
            AND (Command.SpeedRPM >= 0.0)
            AND (Command.SpeedRPM <= MaxRPM)
            AND (Command.RampSec >= 0.1)
            AND (Command.RampSec <= 600.0)
            AND (MaxRPM > 0.0);

    NewGoal := CommandPulse AND ValidCmd;
    IF NewGoal THEN
        AcceptedSequence := Command.Sequence;
        Goal := Command.SpeedRPM * INT_TO_REAL(Command.Direction);
        StageSec := Command.RampSec;

        IF State = MOTOR_WAIT_STOP THEN
            // Never cancel physical-stop gate on a new command.
            PendingReverse := (ABS(Goal) > 0.001);
        ELSE
            StageStart := ProfileRPM;
            StageAge := 0.0;
            IF (ABS(ProfileRPM) > 0.001) AND (ABS(Goal) > 0.001)
               AND ((ProfileRPM > 0.0) <> (Goal > 0.0)) THEN
                StageEnd := 0.0;    // reverse: first stop
                PendingReverse := TRUE;
            ELSIF (ABS(ProfileRPM) < 0.001) AND (NOT StopConfirmed)
                  AND (ABS(Goal) > 0.001) THEN
                State := MOTOR_WAIT_STOP;
                StopAge := 0.0;
                PendingReverse := TRUE;
            ELSE
                StageEnd := Goal;
                PendingReverse := FALSE;
                IF ABS(ProfileRPM) < 0.001 AND ABS(Goal) > 0.001 THEN
                    IF Goal < 0.0 THEN HeldDirection := -1;
                    ELSE HeldDirection := 1; END_IF;
                END_IF;
            END_IF;
            IF State <> MOTOR_WAIT_STOP THEN State := MOTOR_RAMP; END_IF;
        END_IF;
    END_IF;

    CASE State OF
        MOTOR_IDLE:
            ProfileRPM := 0.0;

        MOTOR_RAMP:
            StageAge := MIN(StageSec, StageAge + CycleSec);
            ProfileRPM := StageStart +
                 (StageEnd - StageStart) * (StageAge / StageSec);
            IF StageAge >= StageSec THEN
                ProfileRPM := StageEnd;
                IF ABS(StageEnd) <= 0.001 THEN
                    StopAge := 0.0;
                    State := MOTOR_WAIT_STOP;
                ELSE
                    State := MOTOR_RUN;
                END_IF;
            END_IF;

        MOTOR_WAIT_STOP:
            ProfileRPM := 0.0;
            StopAge := StopAge + CycleSec;
            IF StopConfirmed THEN
                IF ABS(Goal) <= 0.001 THEN
                    PendingReverse := FALSE;
                    State := MOTOR_IDLE;
                ELSE
                    IF Goal < 0.0 THEN HeldDirection := -1;
                    ELSE HeldDirection := 1; END_IF;
                    StageStart := 0.0;
                    StageEnd := Goal;
                    StageAge := 0.0;
                    PendingReverse := FALSE;
                    State := MOTOR_RAMP;
                END_IF;
            ELSIF StopAge >= StopTimeoutSec THEN
                FaultLatched := TRUE;
                State := MOTOR_FAULT;
            END_IF;

        MOTOR_RUN:
            ProfileRPM := Goal;
    END_CASE;
END_IF;

// Enforce a stop request for every blocked or waiting state.
RunRequest := (State = MOTOR_RAMP OR State = MOTOR_RUN)
              AND ABS(ProfileRPM) > 0.001
              AND InterlocksOK AND Enable AND NOT FaultLatched;
ReverseRequest := HeldDirection = -1;
StopRequest := NOT RunRequest;
IF State = MOTOR_FAULT OR State = MOTOR_DISABLED THEN
    ProfileRPM := 0.0;
    RunRequest := FALSE;
    StopRequest := TRUE;
END_IF;
END_FUNCTION_BLOCK
