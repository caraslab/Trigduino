%%
cd C:\src\Trigduino

%%
serialportlist
%%
A = Trigduino("COM4");

A.connect;

A.Calibration = -5e-6;

%% Count
A.NPulses = 10;
A.InterPulseInterval = 1e-4;
A.PulseDuration = 1e-4;

A.info

A.trigger;

%% Rate

Freq = 100;

A.NPulses = 100;

A.InterPulseInterval = 1/(Freq*2); % seconds
A.PulseDuration = 1/(Freq*2);

A.trigger;

%% Trigger one or multiple pulse trains

nTrains = 60;

iti = 4; % seconds

trainDur = A.NPulses*(A.PulseDuration + A.InterPulseInterval);
iti = iti + trainDur;

fprintf('%d trains of\n\t%d pulses\n\tinter-pulse interval = %g\n\tpulse duration = %g\n', ...
    nTrains,A.NPulses,A.InterPulseInterval,A.PulseDuration)

for i = 1:nTrains
    
    A.trigger;

    fprintf('Triggered train %d of %d\n',i,nTrains)
    
    if i < nTrains
        pause(iti)
    else
        pause(trainDur)
    end
end

fprintf(2,'done\n')


%%












%% ANALOG FUNCTIOIN
A.PulseModeOn = false;

%% Arduino sampling rate

A.SamplingRate = 1000;


%% Define what each pulse looks like

pulseDuration = 0.05; % seconds


n = round(A.SamplingRate.*pulseDuration);
% n = 10; % samples

mv = 2^12-1; % [0 4095]

% A.Buffer = mv*ones(1,n); % square wave
% A.Buffer = [round(mv*triang(n)); 0]';
A.Buffer = repmat([round(mv*gausswin(n)); 0],10,1)';

%%

A.trigger;

%% Close the connection
delete(A);

clear A