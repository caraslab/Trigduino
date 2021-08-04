%%
cd C:\Users\Daniel\src\Trigduino

%%
serialportlist
%%
A = Trigduino("COM3");

A.connect;

%% Number of pulses to present

A.NPulses = 50;

%% Inter pulse interval (seconds)

A.InterPulseInterval = 0.025; % seconds

%% Pulse duration (seconds)
A.PulseDuration = 0.025; % seconds





%% ANALOG FUNCTIOIN
A.PulseModeOn = false;

%% Arduino sampling rate

A.SamplingRate = 1000;
%% Define what each pulse looks like

pulseDuration = 0.05; % seconds


n = round(A.SamplingRate.*pulseDuration);
% n = 10; % samples

mv = 2^12-1; % [0 4095]

A.Buffer = mv*ones(1,n); % square wave
% A.Buffer = [round(mv*triang(n)); 0]';
% A.Buffer = [round(mv*gausswin(n)); 0]';

%%

A.trigger;

%% Close the connection
delete(A);

clear A