* Use Arduino Due programmed with `sketch_PWMTrainGen.ino`
# PWM Train Generator — Concise User Manual
## What it is

A timer-driven Arduino Due sketch that outputs **pulse trains** on a **digital pin**.  
Inside each **pulse window**, the pin carries a **square-wave carrier (PWM)** whose **duty cycle** controls the _average open time_ of a shutter. Between pulses and between trains the pin is LOW.

- Default output pin: **D6** (3.3 V TTL).
- Optional compile-time LED at pulse **window** boundaries (off by default).

---
## Requirements

- **Board:** Arduino **Due** (SAM3X8E).
- **Wiring:** D6 → shutter controller TTL input; GND → shutter ground (common ground).
- **Serial:** 115200 baud; line ending = **Newline** (or “Both NL & CR”).

---
## Commands (simple protocol)

|Command|Meaning|Notes|
|---|---|---|
|`R`|Handshake|Replies `R`.|
|`CFG <pulse_us> <ipi_us> <pulses_per_train> <iti_us> <duty_pct> [pwm_hz]`|Configure timing|See parameters below. Echoes `OK …` with resolved values.|
|`GO`|Start|Begins continuous train sequence with current config.|
|`STOP`|Stop|Immediately stops and drives output LOW.|

### Parameters (in `CFG`)

- `pulse_us` — **Pulse window** length (µs).
- `ipi_us` — Inter-pulse interval **within** a train (µs).
- `pulses_per_train` — Number of pulses per train.
- `iti_us` — Inter-train interval (µs).
- `duty_pct` — 0–100. **PWM duty** _inside_ each pulse window.
    - 100 → HIGH for entire window (no carrier toggling).
    - 50 → equal HIGH/LOW segments at the carrier frequency inside the window.        
- `[pwm_hz]` — _(optional)_ Carrier frequency **during** the pulse window (default **50000 Hz**).

**Behavior:** Trains **repeat indefinitely**: pulse windows and IPIs form a train; trains are separated by ITI; sequence loops until `STOP`.

---

## Quick start

1. Open Serial Monitor (115200, newline).
2. Send a config, then `GO`.

**Example (100% duty):**

```
CFG 15000 35000 20 5000000 100 
GO
```
→ Pulse windows: 15 ms, spaced by 35 ms; 20 pulses per train; 5 s between trains; output stays HIGH through each window.

**Same timings at 50% duty:**
```
CFG 15000 35000 20 5000000 50
GO
```

→ Within each 15 ms window the pin toggles at the carrier (default 1 kHz) with 50% duty.

**Make the carrier explicit (e.g., 2 kHz):**
```
CFG 15000 35000 20 5000000 50 2000
GO
```


---

## Notes & limits

- **Voltage:** Due I/O is **3.3 V TTL**. Use a level shifter if the shutter expects 5 V.
- **Time resolution:** Internally ~0.1 µs scheduling; practical PWM **carrier** limit with ISR toggling is ~**20–50 kHz**. For very high carriers, consider hardware PWM gating.
- **LED:** By default **disabled** to avoid overhead. To enable a **window-boundary** indicator only, add at top of sketch:  
    `#define WINDOW_LED 1`

---

## Troubleshooting

- **No response to `GO`:** Ensure you got an `OK …` echo after `CFG`. Check Serial line ending (must send newline).
- **No output on D6:** Verify wiring and ground; try 100% duty to see a solid HIGH during the window.
- **Looks unchanged when switching duty:** If `pulse_us` and `ipi_us` already yield a 50/50 period, `duty=50` matches that. Try a clearly different duty (e.g., 20 or 80) or set `pwm_hz` lower to see toggling on a scope.

---

## Changing the output pin (optional)

Edit at the top of the sketch:

`#define DIGITAL_OUT_PIN 6   // set to your desired Due digital pin`

Recompile and upload.

---

That’s it—configure with `CFG …`, start with `GO`, stop with `STOP`.