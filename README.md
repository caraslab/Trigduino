# Trigduino

Simple Arduino Due + MATLAB toolkit for generating precise, arbitrary pulse trains to control external devices (e.g., stimulus hardware, LEDs, shutters).

## Repository layout

- `Trigduino.m` – MATLAB class that talks to the Arduino over serial.
- `TrigduinoGUI.m` – MATLAB App/UI for configuring and running pulse trains without code.
- `sketch_PulseTrainGen/` – Arduino sketch for the Due that generates the pulse trains.
- `scratch_Trigduino.m` – Small script with example/debug snippets.
- Datasheets/notes: `LM358A_D-2314983.pdf`, `ArduPicLab_ How to modify analog output range of Arduino Due.pdf`.

## Requirements

- **Hardware:** Arduino **Due** (Programming Port via USB).
- **Software:** Arduino IDE (with *Arduino SAM Boards* installed), MATLAB R2019b+ (uses `serialport`).
- **OS:** Windows/macOS/Linux (any OS with a working serial COM/TTY device).
- **Optional:** Simple op-amp/buffer if you need higher-voltage or analog outputs (see PDFs).

## Quick start

1. **Clone** the repo and add it to your MATLAB path.
2. **Flash the Due:**
   - Open Arduino IDE → *File → Open…* → select the sketch in `sketch_PulseTrainGen/`.
   - *Tools → Board:* **Arduino Due (Programming Port)** → select correct Port → **Upload**.
3. **Connect hardware:** Wire your target device to the selected Due digital output pin (TTL level).
4. **Run the GUI (easiest):**
   - In MATLAB: `TrigduinoGUI`
   - Select the serial port, set pulse parameters (frequency, pulse width, count, pin, etc.), then **Preview** or **Run**.
5. **Programmatic control (minimal example):**
   ```matlab
   % Create, connect, configure, run, stop
   td = Trigduino;               % create the interface
   td.connect("COM5");           % your COM/tty device
   cfg = struct( ...
       "pin", 6, ...             % Due digital pin
       "frequency_Hz", 20, ...
       "pulseWidth_us", 500, ...
       "nPulses", 50, ...
       "polarity", "activeHigh", ...
       "startDelay_ms", 0);
   td.configure(cfg);            % send all parameters
   td.preview();                 % optional scope/LED check
   td.run();                     % start generation
   td.stop();                    % stop early (if needed)
   td.disconnect();
   ```

## MATLAB API (overview)

> Exact names may vary slightly; see method help in `Trigduino.m` for signatures and defaults.

- **Construction & I/O**
  - `Trigduino` – create interface object.
  - `connect(port)` / `disconnect()` – open/close serial to the Due.
  - `ping()` – sanity check that the sketch is responsive.
- **Configuration**
  - `configure(cfgStruct)` – set all parameters in one call.
  - Convenience setters for common fields (if you prefer individual calls), e.g., `setPin`, `setFrequency`, `setPulseWidth`, `setCount`, `setPolarity`, `setStartDelay`.
- **Execution**
  - `preview()` – arm with current settings and emit a short test pattern.
  - `run()` – start the full pulse train.
  - `pause()` / `stop()` – control during playback.
- **Utilities**
  - `readback()` – query current configuration from the device.
  - `saveConfig(file)` / `loadConfig(file)` – store/load parameter presets.
  - `version()` – report firmware/software versions.

The **GUI** (`TrigduinoGUI.m`) wraps the same operations with buttons and fields. Typical controls include **Connect**, **Preview**, **Run**, **Pause**, **Stop**, and **Save/Load Config**.

## Typical parameters

- **pin** – Due digital output (e.g., 6).
- **frequency_Hz** – pulse repetition rate.
- **pulseWidth_us** – pulse width (microseconds).
- **nPulses** – number of pulses in a train.
- **polarity** – `"activeHigh"` or `"activeLow"`.
- **startDelay_ms** – delay before the train begins.

> The Arduino sketch programs the Due’s timers/IO to produce deterministic TTL pulses according to these fields; stick to ranges supported by the SAM3X8E and your wiring.

## Notes & safety

- Outputs are **3.3 V TTL** (Due). Level-shift if your device expects 5 V.
- Add buffering/isolators when driving coils/relays or long cables.
- If you need >3.3 V analog, see the included Due DAC range note and LM358A datasheet.

## Troubleshooting

- **“Port in use”:** Close Arduino Serial Monitor and any other apps; `clear` MATLAB objects; power-cycle the Due.
- **No pulses:** Verify `pin` wiring, polarity, and that **Run** (not just **Preview**) is pressed.
- **Timing limits:** Extremely short widths or very high frequencies may be hardware-limited.

## Contributing / License

Open an issue or PR with proposed changes.
If you need a formal license, open an issue to discuss—no license file is currently present in the repo.
