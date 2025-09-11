// Trigduino: High-precision pulse train generator (Arduino Due, SAM3X8E)
// Timer-driven DAC output + onboard LED + dedicated DIGITAL OUT pin that is HIGH while a pulse is active.
// PC protocol unchanged: R, S<int>, N<int>, I<int>, P<int>, B <list>, T

#include <Arduino.h>

// ---------- User-selectable digital output pin ----------
// This pin mirrors pulse activity (HIGH during a pulse, LOW during IPI/idle).
// Choose any valid Due digital pin connected to your external device (e.g., D6).
#ifndef DIGITAL_OUT_PIN
#define DIGITAL_OUT_PIN 6
#endif

// ---------- Configuration ----------
#define DAC_MAX_VALUE      4095
#define MAX_BUFFER_SAMPLES 8192
#define DEFAULT_FS_HZ      1000

// ---------- State (shared with ISR) ----------
volatile uint16_t gBuffer[MAX_BUFFER_SAMPLES];
volatile uint32_t gBufLen = 0;            // samples per pulse
volatile uint32_t gNPulses = 1;           // number of pulses to emit
volatile uint32_t gIPI_us = 0;            // inter-pulse interval (µs)
volatile uint32_t gPulseDur_us = 0;       // stored only (protocol compatibility)
volatile uint32_t gFs_Hz = DEFAULT_FS_HZ; // sampling rate

// Playback bookkeeping
volatile bool     gRunning = false;
volatile bool     gInIPI   = false;
volatile uint32_t gSampleIdx = 0;         // index into gBuffer
volatile uint32_t gPulsesLeft = 0;
volatile uint32_t gIPITicksLeft = 0;      // # of timer ticks to hold 0 between pulses

volatile uint32_t gTicksPerSecond = DEFAULT_FS_HZ; // equals Fs

// ---------- Forward decls ----------
static void configureDAC();
static void configureTC(uint32_t fsHz);
static void startPlayback();
static inline void stopPlayback();
static inline void dacWrite12(uint16_t v);
static uint32_t computeIPITicks(uint32_t ipi_us, uint32_t fsHz);
static void parseLine(String &line);
static inline void ledOn();
static inline void ledOff();
static inline void dioOn();
static inline void dioOff();

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(5000);

  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);
  pinMode(DIGITAL_OUT_PIN, OUTPUT);
  digitalWrite(DIGITAL_OUT_PIN, LOW);

  analogWriteResolution(12);
  configureDAC();
  configureTC(gFs_Hz);

  dacWrite12(0);
}

void loop() {
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.length() > 0) parseLine(line);
  }
}

// ---------- Serial protocol ----------
static void parseLine(String &line) {
  const char cmd = line.charAt(0);
  switch (cmd) {
    case 'R': Serial.println("R"); break;
    case 'S': {
      long fs = line.substring(1).toInt(); if (fs < 1) fs = 1;
      noInterrupts(); gFs_Hz = (uint32_t)fs; gTicksPerSecond = gFs_Hz; configureTC(gFs_Hz); interrupts();
      Serial.print('S'); Serial.println((int)gFs_Hz); break;
    }
    case 'N': {
      long n = line.substring(1).toInt(); if (n < 1) n = 1;
      noInterrupts(); gNPulses = (uint32_t)n; interrupts();
      Serial.print('N'); Serial.println((int)gNPulses); break;
    }
    case 'I': {
      long us = line.substring(1).toInt(); if (us < 0) us = 0;
      noInterrupts(); gIPI_us = (uint32_t)us; interrupts();
      Serial.print('I'); Serial.println((int)gIPI_us); break;
    }
    case 'P': {
      long us = line.substring(1).toInt(); if (us < 0) us = 0;
      noInterrupts(); gPulseDur_us = (uint32_t)us; interrupts();
      Serial.print('P'); Serial.println((int)gPulseDur_us); break;
    }
    case 'B': {
      int sp = line.indexOf(' ');
      String list = (sp >= 0) ? line.substring(sp + 1) : String();
      list.replace("[", ""); list.replace("]", ""); list.replace(" ", "");
      uint32_t count = 0; char *cstr = strdup(list.c_str());
      if (cstr) {
        char *tok = strtok(cstr, ","); noInterrupts();
        while (tok && count < MAX_BUFFER_SAMPLES) {
          long v = atol(tok); if (v < 0) v = 0; if (v > DAC_MAX_VALUE) v = DAC_MAX_VALUE;
          gBuffer[count++] = (uint16_t)v; tok = strtok(NULL, ",");
        }
        gBufLen = count; interrupts(); free(cstr);
      }
      Serial.print('B'); Serial.println((int)count); break;
    }
    case 'T': startPlayback(); break;
    default: break; // ignore unknown
  }
}

// ---------- DAC ----------
static void configureDAC() {
  pmc_enable_periph_clk(ID_DACC);
  DACC->DACC_CR = DACC_CR_SWRST;
  DACC->DACC_MR = DACC_MR_TRGEN_DIS | DACC_MR_WORD_HALF | DACC_MR_TAG_EN | DACC_MR_REFRESH(1) | DACC_MR_STARTUP_8;
  DACC->DACC_CHER = DACC_CHER_CH0; // DAC0
}

static inline void dacWrite12(uint16_t v) {
  while ((DACC->DACC_ISR & DACC_ISR_TXRDY) == 0) { }
  DACC->DACC_CDR = (uint32_t)v; // 12-bit
}

// ---------- Timer Counter (TC0 Ch0) ----------
static void configureTC(uint32_t fsHz) {
  if (fsHz == 0) fsHz = 1;
  pmc_enable_periph_clk(ID_TC0);
  const uint32_t mck = VARIANT_MCK; // 84 MHz
  const uint32_t divisors[4] = {2, 8, 32, 128};
  uint32_t bestDivSel = 0, rc = 0;
  for (uint32_t sel = 0; sel < 4; ++sel) {
    uint32_t clk = mck / divisors[sel]; uint32_t rcCandidate = clk / fsHz;
    if (rcCandidate > 0 && rcCandidate <= 65535) { bestDivSel = sel; rc = rcCandidate; break; }
  }
  if (rc == 0) { bestDivSel = 3; rc = (mck / divisors[bestDivSel]) / fsHz; if (rc == 0) rc = 1; }
  uint32_t tccclks = TC_CMR_TCCLKS_TIMER_CLOCK1 + bestDivSel; // CLOCK1..4
  TC_Configure(TC0, 0, tccclks | TC_CMR_WAVE | TC_CMR_WAVSEL_UP_RC);
  TC_SetRC(TC0, 0, rc);
  TC0->TC_CHANNEL[0].TC_IER = TC_IER_CPCS;
  TC0->TC_CHANNEL[0].TC_IDR = ~TC_IER_CPCS;
  NVIC_EnableIRQ(TC0_IRQn);
}

void TC0_Handler(void) {
  volatile uint32_t status = TC0->TC_CHANNEL[0].TC_SR; (void)status; // clear IRQ
  if (!gRunning || gBufLen == 0) return;

  if (!gInIPI) {
    if (gSampleIdx == 0) { ledOn(); dioOn(); }    // start of a pulse
    if (gSampleIdx < gBufLen) {
      dacWrite12(gBuffer[gSampleIdx++]);
    } else {
      // pulse finished
      ledOff(); dioOff();
      if (gPulsesLeft > 0) gPulsesLeft--;
      if (gPulsesLeft == 0) { dacWrite12(0); stopPlayback(); return; }
      // setup IPI
      uint32_t ticks = computeIPITicks(gIPI_us, gFs_Hz);
      if (ticks > 0) { gInIPI = true; gIPITicksLeft = ticks; dacWrite12(0); if (gIPITicksLeft) gIPITicksLeft--; }
      gSampleIdx = 0; // next pulse
    }
  } else {
    // IPI region: hold low
    dacWrite12(0); ledOff(); dioOff();
    if (gIPITicksLeft > 0) { gIPITicksLeft--; } else { gInIPI = false; }
  }
}

static void startPlayback() {
  if (gBufLen == 0) return;
  noInterrupts();
  gSampleIdx = 0; gPulsesLeft = gNPulses; gInIPI = false; gIPITicksLeft = 0; gRunning = true;
  ledOff(); dioOff();
  TC_Start(TC0, 0);
  interrupts();
}

static inline void stopPlayback() {
  gRunning = false; TC_Stop(TC0, 0); ledOff(); dioOff();
}

static uint32_t computeIPITicks(uint32_t ipi_us, uint32_t fsHz) {
  if (ipi_us == 0 || fsHz == 0) return 0; uint64_t num = (uint64_t)ipi_us * (uint64_t)fsHz + 999999ULL; return (uint32_t)(num / 1000000ULL);
}

static inline void ledOn()  { digitalWrite(LED_BUILTIN, HIGH); }
static inline void ledOff() { digitalWrite(LED_BUILTIN, LOW); }
static inline void dioOn()  { digitalWrite(DIGITAL_OUT_PIN, HIGH); }
static inline void dioOff() { digitalWrite(DIGITAL_OUT_PIN, LOW); }
