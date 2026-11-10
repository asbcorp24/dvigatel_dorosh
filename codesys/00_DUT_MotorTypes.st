TYPE E_MotorState :
(
    MOTOR_DISABLED,
    MOTOR_IDLE,
    MOTOR_RAMP,
    MOTOR_WAIT_STOP,
    MOTOR_RUN,
    MOTOR_FAULT
);
END_TYPE

TYPE ST_MotorCommand :
STRUCT
    SpeedRPM : REAL;
    RampSec : REAL;
    Direction : INT; // +1 / -1
    Sequence : WORD;
END_STRUCT
END_TYPE
