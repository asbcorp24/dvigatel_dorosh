"""Modbus TCP transport example. DRY-RUN by default; production use requires commissioning."""
from __future__ import annotations
import argparse
import time
from pymodbus.client import ModbusTcpClient

# Holding registers: 0-based PDU offsets, NOT 40001-style notation.
# Install: python -m pip install 'pymodbus>=3.7,<4'
# Please confirm the installed pymodbus API before deployment.

def motor_command(client, speed_rpm: float, ramp_sec: float,
                  direction: int, sequence: int, *, execute: bool = False):
    if direction not in (-1, 1):
        raise ValueError("direction must be -1 or +1")
    if not (0.0 <= speed_rpm <= 1500.0):
        raise ValueError("speed outside example range; commission motor limits first")
    if not (0.1 <= ramp_sec <= 600.0):
        raise ValueError("ramp outside permitted range")
    words = [round(speed_rpm * 10), round(ramp_sec * 10),
             1 if direction == 1 else 2]
    if not execute:
        print("DRY RUN: HR[0:3] =", words, "commit HR[4] =", sequence)
        return
    # Only one authorized writer may access the PLC.
    result = client.write_registers(address=0, values=words)
    if result.isError():
        raise RuntimeError(f"parameter write failed: {result}")
    commit = client.write_register(address=4, value=sequence % 65536)
    if commit.isError():
        raise RuntimeError(f"commit write failed: {commit}")

def poll(client):
    reply = client.read_holding_registers(address=100, count=17)
    if reply.isError():
        raise RuntimeError(str(reply))
    w = reply.registers
    signed = (w[2] << 16) | w[3]
    if signed >= 2**31:
        signed -= 2**32
    temp = w[4] if w[4] < 32768 else w[4] - 65536
    return {
        "accepted_sequence": w[0],
        "state": w[1],
        "rpm": signed / 10,
        "pt100_c": None if w[4] == 0x7FFF else temp / 10,
        "frequency_raw": w[5],
        "current_raw": w[6],
        "drive_status_raw": w[7],
        "fault_raw": w[8],
        "feedback_valid": bool(w[10]),
        "stop_confirmed": bool(w[12]),
        "run_permitted": bool(w[16]),
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, default=502)
    ap.add_argument("--execute", action="store_true",
                    help="Explicitly enable network writes")
    ap.add_argument("--speed", type=float, default=0.0)
    ap.add_argument("--ramp", type=float, default=5.0)
    ap.add_argument("--direction", type=int, default=1)
    ns = ap.parse_args()
    if not ns.execute:
        motor_command(None, ns.speed, ns.ramp, ns.direction, 1)
        print("Use --execute only after protective commissioning.")
        return
    with ModbusTcpClient(ns.host, port=ns.port, timeout=2) as client:
        if not client.connect():
            raise ConnectionError("PLC Modbus TCP unreachable")
        # Change heartbeat for 2 seconds BEFORE issuing a command.
        for hb in range(1, 4):
            res = client.write_register(address=3, value=hb)
            if res.isError():
                raise RuntimeError(str(res))
            time.sleep(0.5)
        # WARNING: production clients must continue heartbeat while moving.
        # This example intentionally sends only a STOP command.
        if ns.speed != 0.0:
            raise RuntimeError("Non-zero motion not enabled by this example")
        motor_command(client, 0.0, ns.ramp, ns.direction, 1, execute=True)
        print(poll(client))

if __name__ == "__main__":
    main()
