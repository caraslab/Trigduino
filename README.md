# PWM Train Generator for Arduino Due (with Sync Outputs)

This sketch generates pulse **trains** composed of fixed-duration **pulse windows**. Inside each pulse window, a PWM **carrier** runs at a configurable duty cycle and frequency. Two **non‑PWM sync lines** provide clean logic‑level markers for external hardware:

- **PULSE\_INDICATOR\_PIN** (default **10**): HIGH for the duration of each pulse window.
- **TRAIN\_INDICATOR\_PIN** (default **12**): HIGH for the duration of each train (from first pulse start to last pulse end).

The PWM/carrier itself is on **DIGITAL\_OUT\_PIN** (default **6**) and is only active during pulse windows.

---

## Features

- Microsecond scheduling of pulse and train timing using **TC0** (SAM3X8E) at **MCK/8 ≈ 10.5 MHz** (\~0.095 µs tick).
- PWM **inside** the pulse window with configurable **duty (0–100%)** and **frequency**.
- **Non‑PWM** sync outputs for robust triggering/recording: pulse window (pin 10) and train window (pin 12).
- **Finite** or **infinite** presentations: set `ntrains=0` for infinite.
- **COUNT** query returns the number of trains completed **since last **`` (counter resets on `GO`).
- Optional `WINDOW_LED` to indicate pulse windows with the built‑in LED.

> **Voltage levels:** Arduino Due I/O is **3.3 V**. Do **not** connect directly to 5 V inputs without level shifting.

---

## Pinout (defaults)

- **DIGITAL\_OUT\_PIN = 6** → PWM/carrier output (active only during pulse windows)
- **PULSE\_INDICATOR\_PIN = 10** → High while a pulse window is active (non‑PWM)
- **TRAIN\_INDICATOR\_PIN = 12** → High while a train is active (non‑PWM)
- **LED\_BUILTIN** (optional via `#define WINDOW_LED 1`): mirrors pulse window

You may change pins by editing the `#define` values at the top of the sketch.

---

## Serial Protocol

All commands are ASCII and must end with a **newline** (`\n`). Default serial: **115200 baud**.

### Commands

- `R` → Responds with `R` (handshake/test)
- `CFG <pulse_us> <ipi_us> <pulses_per_train> <iti_us> <duty_pct> [pwm_hz] [ntrains]`
- `GO` → Start playback with the current configuration (resets train counter)
- `STOP` → Stop playback immediately
- `COUNT` → Prints `COUNT=<integer>`; trains completed since last `GO`

### `CFG` Arguments

| Arg | Name               | Units | Description                                                       |
| --- | ------------------ | ----- | ----------------------------------------------------------------- |
| 1   | `pulse_us`         | µs    | Pulse window length (duration of ON window for carrier)           |
| 2   | `ipi_us`           | µs    | Inter‑pulse interval **within** a train                           |
| 3   | `pulses_per_train` | count | Number of pulses per train (minimum 1)                            |
| 4   | `iti_us`           | µs    | Inter‑train interval (time between trains)                        |
| 5   | `duty_pct`         | %     | PWM duty **inside** the pulse window (0–100)                      |
| 6   | `pwm_hz`           | Hz    | *(optional)* Carrier frequency; if omitted, current value is kept |
| 7   | `ntrains`          | count | *(optional)* Number of trains; **0 = infinite**                   |

On success, the device responds with a line echoing the applied parameters.

### Examples

**Infinite trains at 10 kHz carrier, 100% duty**

```
CFG 15000 35000 20 5000000 100 10000 0
GO
```

**Fifteen trains at 20 kHz carrier, 50% duty**

```
CFG 20000 30000 10 1000000 50 20000 15
GO
```

**Query count and stop**

```
COUNT
STOP
```

---

## Timing Notes

- The timer runs at **MCK/8 ≈ 10.5 MHz**; all microsecond delays are **ceil‑quantized** to \~0.095 µs ticks.
- Inside a pulse window, the PWM alternates using the configured period and duty. Edge cases are handled to avoid zero‑length segments when duty is between 0 and 100.
- `duty_pct = 0` → Carrier stays LOW during pulse windows (sync pins still indicate pulse/train).
- `duty_pct = 100` → Carrier stays HIGH during pulse windows (no toggling inside the window).

---

## Build & Flash

1. Open the sketch in the **Arduino IDE**.
2. Select **Board:** *Arduino Due (Programming Port)*.
3. Select the correct **Port**.
4. Upload.
5. Open **Serial Monitor** at **115200 baud**, set **line ending** to **Newline** (`\n`).

> **Tip:** You can also drive the device from Python, MATLAB, or any environment that can open a serial port and send newline‑terminated strings.

---

## Quick MATLAB Snippet

```matlab
s = serialport("COM5", 115200);
configureTerminator(s, "LF");
writeline(s, "R");            % handshake
writeline(s, "CFG 15000 35000 20 5000000 100 10000 5");
writeline(s, "GO");
pause(2);
writeline(s, "COUNT");
resp = readline(s)  % e.g., "COUNT=2"
writeline(s, "STOP");
```

---

## Electrical / Safety

- Outputs are **3.3 V CMOS**. Use proper level shifting if a 5 V system is required.
- Sync lines on pins **10** and **12** are **non‑PWM** and intended for **triggering/syncing** external equipment.
- Ensure that connected equipment shares a **common ground**.

---

## Troubleshooting

- **No PWM output:** Verify `duty_pct > 0`, `pulses_per_train ≥ 1`, and the correct **DIGITAL\_OUT\_PIN** wiring.
- **COUNT always 0:** `COUNT` resets on `GO`; query after at least one train completes.
- **Change pins/frequency:** Edit the `#define` section at the top of the sketch.

---


