

// Onboard LED properties
const int ledPin = LED_BUILTIN;// the number of the LED pin

// Digital trigger pin
const int digPin = 12;

// Analog DAC0 pin (DUE)
const int dacPin = 76; // DUE DAC0 pin = 76, DAC1 pin = 77
const int dacRes = 12; // 12-bit max resolution for DUE
unsigned int Fs = 1000; // sampling rate for DAC


// Private Trigger properties
unsigned long trigOnset = 0; // Records trigger onset timestamps

// Setable Pulse train properties
unsigned int ipi = 250000; // inter-pulse interval (microseconds)
unsigned int nPulses = 10; // number of pulses to present; 0 = infinite
int pulseBuffer[20000]; // preallocated buffer gets overwritten with new data
unsigned int bufferSize = 0;
unsigned int pulseDuration = 250000; // digital pulse duration (microseconds)
bool pulseModeOn = true;


void setup() {

  Serial.begin(115200);

  while (!Serial) {
    // wait for serial port to connect
  }
  analogWriteResolution(dacRes);
  pinMode(ledPin, OUTPUT);
  pinMode(digPin, OUTPUT);
  establishConnection();
}

void establishConnection() {

  while (Serial.available() <= 0) {
    // wait for computer to respond
    readSerial();
  }


  // blink onboad LED to indicate success
  for (int i = 0; i <= 4; i++) {
    digitalWrite(ledPin, HIGH);
    delay(250);
    digitalWrite(ledPin, LOW);
    delay(250);
  }
}

void loop() {
  readSerial();
}


void playDigital() {
  
  trigOnset = micros();

  for (unsigned int j = 0; j < nPulses; j ++) {
    digitalWrite(ledPin, HIGH);
    digitalWrite(digPin, HIGH);
    delayMicroseconds(pulseDuration); // delay next update by artificial sampling rate
    digitalWrite(ledPin, LOW);
    digitalWrite(digPin, LOW);
    delayMicroseconds(ipi);
  } // j

} // playDigital()

void playBuffer() {

  unsigned long dt = 1000000 / Fs; // sample interval s -> us

  
  trigOnset = micros();

  for (unsigned int j = 0; j < nPulses; j ++) {
    digitalWrite(ledPin, HIGH);

    for (unsigned int i = 0; i < bufferSize; i++) {
        analogWrite(DAC0, pulseBuffer[i]);
        delayMicroseconds(dt); // delay next update by artificial sampling rate
    } // i
    
    analogWrite(dacPin,0); // set DAC to 0 for duration of inter-pulse interval
    digitalWrite(ledPin, LOW);
    if (j < nPulses - 1) {
        delayMicroseconds(ipi);
    }
  } // j


 // Serial.println("done");
} // playBuffer()

void readSerial() {

  if (Serial.available() == 0) {
    return;
  }

  char ctrlChar = Serial.read();

  delay(200);

  switch (ctrlChar) {
    case 'M': // Pulse Mode On
      {
        pulseModeOn = Serial.parseInt();
        Serial.print("M");
        Serial.println(pulseModeOn,DEC);
        break;
      }
    case 'T': // Trigger pulse train
      {
        if (pulseModeOn == true) {
          playDigital();
        } else {
          playBuffer();
        }
        break;
      }

    case 'I': // Set inter-pulse interval
      {
        ipi = Serial.parseInt();
        Serial.print("I");
        Serial.println(ipi, DEC);
        break;
      }

    case 'P': // Set digital pulse duration (microseconds) if pulseModeOn = true
      {
        pulseDuration = Serial.parseInt();
        Serial.print("P");
        Serial.println(pulseDuration, DEC);
        break;
      }
      
    case 'N': // Set number of pulses
      {
        nPulses = Serial.parseInt();
        Serial.print("N");
        Serial.println(nPulses, DEC);
        break;
      }


    case 'B': // Set pulse buffer
      {
        //delay(2);
          int i = 0;
          while (Serial.available() > 0) {
              pulseBuffer[i++] = Serial.parseInt();
          }
        // reflect back size of new buffer size
        bufferSize = i-1;
        Serial.print('B');
        Serial.println(bufferSize, DEC);
        break;
      }

    case 'R': // Computer ready
      {
        Serial.println('R');
        break;
      }

    case 'S': // Set sampling rate for DAC
      {
        Fs = Serial.parseInt();
        Serial.print('S');
        Serial.println(Fs);
        break;
      }

  }

  Serial.flush();
}
