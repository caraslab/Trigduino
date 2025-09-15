# DuePulseTrainGUI — User Guide

A MATLAB app to parameterize and trigger pulse trains on an **Arduino Due**. It sends ASCII serial commands and provides live visualization and train counting.

---

## Requirements

* **MATLAB** R2019b or newer (uses `serialport`, `uifigure`, `uiaxes`, etc.).
* **Arduino Due** running firmware that implements the protocol below.
* A USB serial connection (e.g., `COM3`, `/dev/ttyACM0`).

---

## Quick Start

1. **Launch**

   ```matlab
   app = DuePulseTrainGUI;   % or just DuePulseTrainGUI to auto-clear handle
   ```
2. **Connect**

   * `Connection ▸ Port` → choose your COM port (use **Refresh Ports** if needed).
   * `Connection ▸ Baud Rate` → choose the device baud (defaults to **115200**).
   * `Connection ▸ Connect`.
   * Status bar will show “Connected: …”.
3. **Set Parameters**

   * Choose a mode tab:

     * **Intervals**: Pulse (ms), IPI (ms), Pulses/Train.
     * **Rate / Duration**: Pulse (ms), Rate (Hz), Train Dur (s).
   * Set **common** controls (right side): ITI (s), Duty (%), PWM (Hz), Trains (0 = ∞).
   * Plots update as you type.
4. **Apply & Run**

   * Click **Apply Config** to send `CFG …` and refresh plots.
   * Click **GO** to start. Train count shows **“Trains: N / target”**.
   * Click **STOP** to halt immediately.
5. **Disconnect**

   * `Connection ▸ Disconnect` when finished (the app also cleans up on close).

<img width="1202" height="774" alt="image" src="https://github.com/user-attachments/assets/ffba5a1e-4f66-44a5-937f-a2d6070fe35b" />

---

## What the GUI Shows

* **Parameter Tabs (left)**

  * **Intervals**: Explicit pulse width, inter-pulse interval, and pulses per train.
  * **Rate / Duration**: Specify pulse width + rate + total train duration. The app computes IPI and the number of pulses that fit.
* **Common Controls (right)**

  * **ITI (s)**: Inter-train interval.
  * **Duty (%)**: PWM duty cycle (0–100) used inside each pulse window.
  * **PWM (Hz)**: Carrier during pulse windows.
  * **Trains (0=∞)**: Number of trains per **GO** (0 means run continuously).
* **Buttons**

  * **Apply Config** — sends the current parameters (`CFG …`) and updates plots.
  * **GO** — starts stimulus, **resets train counter to 0**, begins periodic count polling.
  * **STOP** — stops stimulus and fetches final count.
  * **Ping (R)** — simple round-trip test.
* **Visualization**

  * **Train Envelope**: Stair plot of pulse windows across a train. Title shows train length and train count setting.
  * **PWM within a Pulse (zoom)**: First pulse window expanded to show PWM high/low edges (up to 10 carrier periods or the pulse length).
* **Device Log**

  * Read-only scrolling log of device lines (and commands the app sends).
* **Status Bar**

  * Latest device/status message.
* **Train Counter**

  * Large label: `Trains: done / target` (∞ if target is 0). Auto-stops the background poller when target reached.

---

## Serial Protocol (device side)

The app speaks simple ASCII lines terminated by newline (MATLAB `serialport` default **LF**). Your firmware should accept these commands and print human-readable responses.

### Commands sent by the GUI

* `R` — ping (you can echo or print any short reply).
* `GO` — start playback using the **last applied** configuration.
* `STOP` — stop playback.
* `COUNT` — request number of **completed trains** (see reply format below).
* `CFG <pulse_us> <ipi_us> <pulses_per_train> <iti_us> <duty_pct> <pwm_hz> <ntrains>`

  * Units: microseconds/percent/Hz/integers.
  * `ntrains = 0` ⇒ run indefinitely until `STOP`.

### Expected device replies

* For `COUNT`:

  * `COUNT=<integer>` (e.g., `COUNT=12`)
* For others:

  * Any informative line(s) are shown in the Device Log and Status bar.

**Notes**

* The app **resets its internal counter to 0** on **GO** and immediately polls `COUNT` once, then polls every \~0.5 s while running.
* If `ntrains > 0` and the reported `COUNT` ≥ `ntrains`, the app stops its polling timer (device may still be idle and ready).

---

## Parameter Details & Rules

* **Intervals mode**

  * Pulse width = `pulse_us` (≥1 µs)
  * IPI = `ipi_us` (≥0)
  * Pulses/Train = `n` (≥1)
* **Rate / Duration mode**

  * Rate (Hz) ⇒ period\_us = round(1e6 / rate)
  * IPI derived as `period_us – pulse_us` (≥0).
  * Pulses/Train computed to fit within `train_dur_s`:

    ```
    if train_us <= pulse_us → n = 1
    else n = floor((train_us - pulse_us)/period_us) + 1
    ```
* **Common**

  * ITI (s) ⇒ `iti_us` (≥0)
  * Duty (%) clamped to \[0, 100]
  * PWM (Hz) ≥ 1
  * Trains: 0 = infinite; otherwise positive integer target.

*Defaults on launch*: Pulse 15 ms, IPI 35 ms, Pulses/Train 20; ITI 5 s; Duty 100%; PWM 10 kHz; Trains 0 (∞). Rate tab defaults: Pulse 15 ms, Rate 20 Hz, Train 1.0 s.

---

## Tips & Troubleshooting

* **No ports listed** → `Connection ▸ Refresh Ports`, check USB cable/driver, or Arduino reset.
* **Baud mismatch** → match the GUI **Baud Rate** to firmware.
* **Nothing happens on GO** → click **Apply Config** first to send `CFG …`; check Device Log for errors.
* **COUNT never updates** → ensure firmware prints `COUNT=<n>` on `COUNT` requests.
* **Terminators** → MATLAB uses LF by default; Arduino `Serial.println()` is fine. (CRLF also works if you print both; the app ignores blank lines.)

---

## Example Session

1. Select `COM4` and `115200`, click **Connect**.
2. Choose **Rate / Duration**, set Pulse **10 ms**, Rate **25 Hz**, Train Dur **2 s**.
3. Set ITI **3 s**, Duty **50%**, PWM **20000 Hz**, Trains **10**.
4. Click **Apply Config** (plots update; config sent).
5. Click **GO** (counter resets to 0; begins running).
6. Observe `Trains: … / 10` increment; when it reaches **10**, polling stops.
7. Click **Disconnect**.

---

## Developer Notes

* Asynchronous line handling via `configureCallback(sp,"terminator",…)`.
* Background **COUNT** polling every 0.5 s (`timer`), with extra immediate polls after **GO/STOP**.
* The app cleans up timers and serial state on **delete**.

---

*Happy stimulating!*
