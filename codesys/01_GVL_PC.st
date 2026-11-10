VAR_GLOBAL
    // Explicitly map these words into Modbus TCP holding registers in Device Tree.
    // 0..5: PC request. 100..116: PLC telemetry.
    Holding : ARRAY[0..127] OF WORD;

    // Must be commissioned ON SITE; no automatic activation from Ethernet.
    CommissionEnable : BOOL := FALSE;
    ConfigValid : BOOL := FALSE;
    PGFeedbackProven : BOOL := FALSE;
    HardwareSafetyOK : BOOL := FALSE;

    // Assign IO in device mappings, not hard-coded addresses.
    Pt100TemperatureC : REAL;
    Pt100InputValid : BOOL;
END_VAR
