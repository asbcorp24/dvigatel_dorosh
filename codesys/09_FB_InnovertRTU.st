FUNCTION_BLOCK FB_InnovertRTU
VAR_INPUT
    EnablePort : BOOL;
    ComPortNumber : UDINT; // Must be confirmed on PLC200 hardware; zero disables.
    SlaveId : USINT := 1;
    Baudrate : UDINT := 38400;
    EnableWrites : BOOL;   // FALSE until verified commissioning.
    CommandPermitted : BOOL; // Set only after hardware + PG + Pt100 and TCP watchdog.
    SetFrequency : WORD;    // 0.01 Hz units after checking P00.00.
    SetControl : WORD;      // manual confirms 0x0001 forward, 0x0003 reverse, 0x0004 stop.
    CycleSec : REAL := 0.02;
END_VAR
VAR_OUTPUT
    PortActive : BOOL;
    Busy : BOOL;
    Healthy : BOOL;
    LastError : BOOL;
    ErrorCount : UDINT;
    OkCount : UDINT;
    LastOperation : UINT;
    LastFailedOperation : UINT;
    SpeedRaw : WORD;
    StatusRaw : WORD;
    FrequencyRaw : WORD;
    CurrentRaw : WORD;
    FaultRaw : WORD;
    SpeedFresh : BOOL;
    StatusFresh : BOOL;
    TelemetryFresh : BOOL;
    WriteFrequencyAck : BOOL;
    WriteControlAck : BOOL;
    LastWrittenFrequency : WORD;
    LastWrittenControl : WORD;
END_VAR
VAR
    Com : OCL.COM_Control;
    Request : OCL.MB_SerialRequest;
    State : UINT := 0;
    Step : UINT := 0;
    RequestExecute : BOOL;
    FC : OCL.MB_FC;
    RegisterAddress : UINT;
    Payload : WORD;
    StepAge : REAL;
    SpeedAge : REAL := 10000.0;
    StatusAge : REAL := 10000.0;
    CurrentAge : REAL := 10000.0;
    FaultAge : REAL := 10000.0;
    FrequencyAge : REAL := 10000.0;
    PendingFrequency : WORD;
    PendingControl : WORD;
    HadWriteFrequencyAck : BOOL;
    HadWriteControlAck : BOOL;
    ErrorStreak : UINT;
    WriteEligible : BOOL;
    IsWrite : BOOL;
    ReadyPort : BOOL;
END_VAR

// One FB owns one physical port. Never create a second Modbus COM Port
// on the same RS-485 interface in the CODESYS Device Tree.
SpeedFresh := FALSE;
StatusFresh := FALSE;
TelemetryFresh := FALSE;
WriteFrequencyAck := FALSE;
WriteControlAck := FALSE;
LastError := FALSE;
Busy := (State = 20);
SpeedAge := MIN(10000.0, SpeedAge + CycleSec);
StatusAge := MIN(10000.0, StatusAge + CycleSec);
FrequencyAge := MIN(10000.0, FrequencyAge + CycleSec);
CurrentAge := MIN(10000.0, CurrentAge + CycleSec);
FaultAge := MIN(10000.0, FaultAge + CycleSec);

// Avoid opening unspecified COM ports.
ReadyPort := EnablePort AND (ComPortNumber > 0);
Com(
    xEnable := ReadyPort,
    udiComPort := ComPortNumber,
    udiBaudrate := Baudrate,
    udiByteSize := 8,
    eParity := OCL.COM_PARITY.NONE,
    eStopBit := OCL.COM_STOPBIT.ONE
);
PortActive := Com.xActive AND NOT Com.xError;

// Keep one request FB called EVERY PLC task with a rising-edge Execute.
Request(
    xExecute := RequestExecute,
    tTimeout := T#300MS,
    usiRetry := 0,
    hCom := Com.hCom,
    xIsAsciiMode := FALSE,
    usiSlaveId := SlaveId,
    eFuncCode := FC,
    uiDataAddr := RegisterAddress,
    uiDataCount := 1,
    pData := ADR(Payload),
    szSize := SIZEOF(Payload)
);

IF NOT PortActive THEN
    State := 0;
    Step := 0;
    RequestExecute := FALSE;
    ErrorStreak := 0;
    SpeedAge := 10000.0;
    StatusAge := 10000.0;
    Healthy := FALSE;
ELSE
    CASE State OF
    0: // start from read-only polling every time port activates
        Step := 0;
        State := 10;
    10: // choose next operation; readings are serialized.
        RequestExecute := FALSE;
        Payload := 0;
        FC := OCL.MB_FC.READ_HOLDING_REGISTERS;
        IsWrite := FALSE;
        CASE Step OF
        0: RegisterAddress := 16#8107; // RPM
        1: RegisterAddress := 16#8118; // run status
        2: RegisterAddress := 16#8102; // output frequency
        3: RegisterAddress := 16#810A; // output current
        4: RegisterAddress := 16#812B; // fault code
        5:
            // Writing is NEVER enabled by merely connecting the PLC to a PC.
            WriteEligible := EnableWrites AND CommandPermitted
                           AND Healthy AND (SpeedAge < 0.8)
                           AND (StatusAge < 0.8);
            IF WriteEligible THEN
                PendingFrequency := SetFrequency;
                PendingControl := SetControl;
                Payload := PendingFrequency;
                RegisterAddress := 16#0000;
                FC := OCL.MB_FC.WRITE_SINGLE_REGISTER;
                IsWrite := TRUE;
            ELSE
                Step := 0;
                RegisterAddress := 16#8107;
            END_IF;
        6:
            // Cannot write command without a successfully acked frequency write.
            IF HadWriteFrequencyAck AND EnableWrites AND CommandPermitted THEN
                Payload := PendingControl;
                RegisterAddress := 16#8000;
                FC := OCL.MB_FC.WRITE_SINGLE_REGISTER;
                IsWrite := TRUE;
            ELSE
                Step := 0;
                RegisterAddress := 16#8107;
            END_IF;
        ELSE
            Step := 0;
            RegisterAddress := 16#8107;
        END_CASE;
        LastOperation := Step;
        State := 20;
    20: // Hold execute through busy and until Done or Error
        RequestExecute := TRUE;
        IF Request.xDone THEN
            OkCount := OkCount + 1;
            ErrorStreak := 0;
            IF IsWrite THEN
                IF Step = 5 THEN
                    HadWriteFrequencyAck := TRUE;
                    LastWrittenFrequency := PendingFrequency;
                    WriteFrequencyAck := TRUE;
                ELSIF Step = 6 THEN
                    HadWriteControlAck := TRUE;
                    LastWrittenControl := PendingControl;
                    WriteControlAck := TRUE;
                END_IF;
            ELSE
                CASE Step OF
                0:
                    SpeedRaw := Payload;
                    SpeedAge := 0.0;
                    SpeedFresh := TRUE;
                1:
                    StatusRaw := Payload;
                    StatusAge := 0.0;
                    StatusFresh := TRUE;
                2:
                    FrequencyRaw := Payload;
                    FrequencyAge := 0.0;
                3:
                    CurrentRaw := Payload;
                    CurrentAge := 0.0;
                4:
                    FaultRaw := Payload;
                    FaultAge := 0.0;
                END_CASE;
            END_IF;
            State := 30;
        ELSIF Request.xError THEN
            ErrorCount := ErrorCount + 1;
            LastError := TRUE;
            LastFailedOperation := Step;
            ErrorStreak := ErrorStreak + 1;
            HadWriteFrequencyAck := FALSE;
            HadWriteControlAck := FALSE;
            SpeedAge := 10000.0; // fail closed even if status register still has data
            StatusAge := 10000.0;
            State := 30;
        END_IF;
    30: // create falling edge before next request
        RequestExecute := FALSE;
        State := 40;
    40:
        IF Step >= 6 THEN
            Step := 0;
            HadWriteFrequencyAck := FALSE;
        ELSE
            Step := Step + 1;
        END_IF;
        State := 10;
    END_CASE;
END_IF;

Healthy := PortActive AND (ErrorStreak < 3)
           AND (SpeedAge < 0.8) AND (StatusAge < 0.8);
TelemetryFresh := Healthy AND (FrequencyAge < 2.0)
                  AND (CurrentAge < 2.0) AND (FaultAge < 2.0);
Busy := State = 20;
END_FUNCTION_BLOCK
