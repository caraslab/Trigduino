%%
serialportlist
%%
A = Trigduino("COM3");

A.connect;

%%

A.SamplingRate = 100;

%%

A.NPulses = 50;

%%

A.InterPulseInterval = .2; % seconds

%%
n = 20; % samples

mv = 2^12-1; % [0 4095]

% A.Buffer = mv*ones(1,n);
% A.Buffer = [round(mv*triang(n)); 0]';
A.Buffer = [round(mv*gausswin(n)); 0]';

%%

A.trigger;

%%
delete(A);

clear A