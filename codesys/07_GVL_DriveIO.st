VAR_GLOBAL
    // Link via CODESYS Modbus Serial Device I/O Mapping.
    // NEVER assume default values mean communication is healthy.
    SpeedRaw : WORD;
    StatusRaw : WORD;
    FrequencyRaw : WORD;
    CurrentRaw : WORD;
    FaultCodeRaw : WORD;
    SpeedResponsePulse : BOOL;
    StatusResponsePulse : BOOL;
    DriveReadFresh : BOOL;
    DriveFault : BOOL;

    // Final outputs are NOT directly mapped to a write device in this version.
    // Implement an acknowledged, single-in-flight Modbus RTU scheduler.
    PendingFrequencyWord : WORD;
    PendingControlWord : WORD;
END_VAR
