#include <Arduino.h>

// Optional: LED indicator at pulse-window boundaries (not per-PWM edge)
#ifndef WINDOW_LED
#define WINDOW_LED 0
#endif

// ====== User configuration ======
#ifndef DIGITAL_OUT_PIN
#define DIGITAL_OUT_PIN 6
#endif
#define DEFAULT_PWM_HZ 50000  // carrier used only during pulse windows --- 50000 or less

// ====== Timing base (TC0, MCK/8) ======
static const uint32_t MCK = VARIANT_MCK; // 84 MHz
static const uint32_t TC_DIV = 8;        // -> 10.5 MHz tick (~0.095us)

// ====== State ======
volatile bool     gRunning = false;

// Config
volatile uint32_t gPulseDur_us = 15000;   // pulse window length
volatile uint32_t gIPI_us      = 35000;   // between pulses (within train)
volatile uint32_t gNPulses     = 20;      // pulses per train
volatile uint32_t gITI_us      = 5000000; // between trains
volatile uint32_t gDuty_pct    = 100;     // PWM duty inside pulse window
volatile uint32_t gPWM_Period_us = 1000000UL / DEFAULT_PWM_HZ;

// Derived for PWM inside pulse
volatile uint32_t gTon_us  = 0;
volatile uint32_t gToff_us = 0;

// Counters
volatile uint32_t gPulsesLeft = 0;
volatile uint32_t gPulseTimeLeft_us = 0; // remaining time in current pulse window

// Output pin fast access (Due PIO)
static Pio*     gDioPort = nullptr;
static uint32_t gDioMask = 0;

// Phase enum
enum Phase : uint8_t { IDLE=0, PULSE_HIGH, PULSE_LOW, BETWEEN_PULSES, BETWEEN_TRAINS };
volatile Phase gPhase = IDLE;

// ====== Helpers ======
static inline void pinHigh() { if (gDioPort) gDioPort->PIO_SODR = gDioMask; }
static inline void pinLow()  { if (gDioPort) gDioPort->PIO_CODR = gDioMask; }

static inline void windowLED_on()  {
#if WINDOW_LED
  digitalWrite(LED_BUILTIN, HIGH);
#endif
}
static inline void windowLED_off() {
#if WINDOW_LED
  digitalWrite(LED_BUILTIN, LOW);
#endif
}

static inline uint32_t usToRC(uint32_t usec) {
  uint64_t clk = (uint64_t)(MCK / TC_DIV);
  uint64_t ticks = (usec == 0) ? 1ULL : ((uint64_t)usec * clk + 999999ULL) / 1000000ULL; // ceil
  if (ticks < 1ULL) ticks = 1ULL;
  if (ticks > 0xFFFFFFFFULL) ticks = 0xFFFFFFFFULL;
  return (uint32_t)ticks;
}

static inline void scheduleNext_us(uint32_t dt_us) {
  TC_SetRC(TC0, 0, usToRC(dt_us));
}

static void tcConfigure() {
  pmc_enable_periph_clk(ID_TC0);
  // TCCLKS: MCK/8
  TC_Configure(TC0, 0, TC_CMR_TCCLKS_TIMER_CLOCK2 | TC_CMR_WAVE | TC_CMR_WAVSEL_UP_RC);
  scheduleNext_us(1000);
  TC0->TC_CHANNEL[0].TC_IER = TC_IER_CPCS;
  TC0->TC_CHANNEL[0].TC_IDR = ~TC_IER_CPCS;
  NVIC_EnableIRQ(TC0_IRQn);
}

static inline void tcStart() { TC_Start(TC0, 0); }
static inline void tcStop()  { TC_Stop(TC0, 0); }

static void resolvePWM() {
  uint32_t P = gPWM_Period_us;
  if (P == 0) P = 1;
  uint32_t ton  = (gDuty_pct >= 100) ? P : (gDuty_pct == 0 ? 0 : (uint32_t)((P * (uint64_t)gDuty_pct + 99ULL)/100ULL));
  if (ton > P) ton = P;
  uint32_t toff = P - ton;
  // avoid zero-length segments inside ISR scheduling
  if (ton  == 0 && gDuty_pct > 0) ton  = 1;
  if (toff == 0 && gDuty_pct < 100) toff = 1;
  gTon_us = ton; gToff_us = toff;
}

static void startTrainLoop() {
  if (gNPulses == 0) return;
  noInterrupts();
  resolvePWM();
  gPulsesLeft = gNPulses;
  gPulseTimeLeft_us = gPulseDur_us;
  gPhase = (gDuty_pct == 0) ? PULSE_LOW : PULSE_HIGH; // start inside pulse
  gRunning = true;
  windowLED_on();
  if (gPhase == PULSE_HIGH) pinHigh(); else pinLow();
  scheduleNext_us(min(gPhase == PULSE_HIGH ? gTon_us : gToff_us, gPulseTimeLeft_us));
  tcStart();
  interrupts();
}

static void stopAll() {
  noInterrupts();
  gRunning = false; gPhase = IDLE; tcStop(); pinLow(); windowLED_off();
  interrupts();
}

void TC0_Handler() {
  volatile uint32_t s = TC0->TC_CHANNEL[0].TC_SR; (void)s;
  if (!gRunning) return;

  switch (gPhase) {
    case PULSE_HIGH: {
      uint32_t step = min(gTon_us, gPulseTimeLeft_us);
      if (gPulseTimeLeft_us > 0) gPulseTimeLeft_us -= step;
      pinLow();
      if (gPulseTimeLeft_us == 0) {
        windowLED_off();
        gPhase = BETWEEN_PULSES; // end of this pulse window
        scheduleNext_us(gIPI_us);
      } else if (gToff_us > 0) {
        gPhase = PULSE_LOW;
        scheduleNext_us(min(gToff_us, gPulseTimeLeft_us));
      } else {
        // 100% duty: stay high segments only
        pinHigh();
        scheduleNext_us(min(gTon_us, gPulseTimeLeft_us));
      }
    } break;

    case PULSE_LOW: {
      uint32_t step = min(gToff_us, gPulseTimeLeft_us);
      if (gPulseTimeLeft_us > 0) gPulseTimeLeft_us -= step;
      if (gPulseTimeLeft_us == 0) {
        gPhase = BETWEEN_PULSES;
        scheduleNext_us(gIPI_us);
      } else {
        pinHigh();
        gPhase = PULSE_HIGH;
        scheduleNext_us(min(gTon_us, gPulseTimeLeft_us));
      }
    } break;

    case BETWEEN_PULSES: {
      // start next pulse or end train
      if (gPulsesLeft > 0) gPulsesLeft--;
      if (gPulsesLeft > 0) {
        gPulseTimeLeft_us = gPulseDur_us;
        windowLED_on();
        if (gDuty_pct == 0) { gPhase = PULSE_LOW;  pinLow();  scheduleNext_us(min(gToff_us, gPulseTimeLeft_us)); }
        else                { gPhase = PULSE_HIGH; pinHigh(); scheduleNext_us(min(gTon_us,  gPulseTimeLeft_us)); }
      } else {
        gPhase = BETWEEN_TRAINS;
        scheduleNext_us(gITI_us);
      }
    } break;

    case BETWEEN_TRAINS: {
      // continuous trains until STOP
      gPulsesLeft = gNPulses;
      gPulseTimeLeft_us = gPulseDur_us;
      windowLED_on();
      if (gDuty_pct == 0) { gPhase = PULSE_LOW;  pinLow();  scheduleNext_us(min(gToff_us, gPulseTimeLeft_us)); }
      else                { gPhase = PULSE_HIGH; pinHigh(); scheduleNext_us(min(gTon_us,  gPulseTimeLeft_us)); }
    } break;

    default: {
      stopAll();
    } break;
  }
}

// ====== Serial protocol ======
// CFG <pulse_us> <ipi_us> <pulses_per_train> <iti_us> <duty_pct> [pwm_hz]
static void applyCFG(uint32_t pulse_us, uint32_t ipi_us, uint32_t nper, uint32_t iti_us, uint32_t duty, uint32_t pwm_hz) {
  if (duty > 100) duty = 100;
  if (nper == 0) nper = 1;
  if (pwm_hz > 0) gPWM_Period_us = (uint32_t)(1000000UL / pwm_hz);
  noInterrupts();
  gPulseDur_us = pulse_us > 0 ? pulse_us : 1;
  gIPI_us      = ipi_us;
  gNPulses     = nper;
  gITI_us      = iti_us;
  gDuty_pct    = duty;
  resolvePWM();
  interrupts();
  Serial.print("OK pulse="); Serial.print(gPulseDur_us);
  Serial.print(" ipi=");   Serial.print(gIPI_us);
  Serial.print(" n=");     Serial.print(gNPulses);
  Serial.print(" iti=");   Serial.print(gITI_us);
  Serial.print(" duty=");  Serial.print(gDuty_pct);
  Serial.print(" pwmHz="); Serial.println((uint32_t)(1000000UL / gPWM_Period_us));
}

static void parseLine(String ln) {
  ln.trim(); if (!ln.length()) return;
  if (ln == "R") { Serial.println("R"); return; }
  if (ln == "GO") { startTrainLoop(); return; }
  if (ln == "STOP") { stopAll(); return; }

  if (ln.startsWith("CFG")) {
    // Expect at least 5 ints; optional 6th = pwm_hz
    uint32_t v[6] = {0,0,0,0,0,0}; int idx=0; int pos=3;
    while (idx<6) {
      while (pos<(int)ln.length() && ln.charAt(pos)==' ') pos++;
      if (pos>=(int)ln.length()) break;
      int next = ln.indexOf(' ', pos);
      String tok = (next<0) ? ln.substring(pos) : ln.substring(pos,next);
      v[idx++] = (uint32_t)tok.toInt();
      if (next<0) break; else pos = next+1;
    }
    if (idx>=5) {
      applyCFG(v[0], v[1], v[2], v[3], v[4], (idx>=6)?v[5]:0);
    } else {
      Serial.println("ERR CFG needs: pulse_us ipi_us pulses_per_train iti_us duty_pct [pwm_hz]");
    }
    return;
  }

  Serial.println("ERR unknown");
}

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(5000);
#if WINDOW_LED
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);
#endif
  pinMode(DIGITAL_OUT_PIN, OUTPUT);
  digitalWrite(DIGITAL_OUT_PIN, LOW);
  gDioPort = g_APinDescription[DIGITAL_OUT_PIN].pPort;
  gDioMask = g_APinDescription[DIGITAL_OUT_PIN].ulPin;
  tcConfigure();
}

void loop() {
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    parseLine(line);
  }
}
