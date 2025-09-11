classdef Trigduino < handle
    % Trigduino Controller for Arduino-based pulse train generation via serial.
    %
    % Trigduino provides a MATLAB interface to an Arduino (e.g., Due)
    % that plays back a user-specified digital pulse buffer or generates
    % pulse trains from simple parameters. The class manages the serial
    % connection, parameter handshakes, and buffer transfer.
    %
    % Properties (public)
    %   Buffer      - Row vector of nonnegative integers (≤ 4096) sent to the
    %                 device as the playback buffer. Setting this property
    %                 immediately writes the buffer to the Arduino.
    %   NPulses     - Positive integer number of pulses per train.
    %   InterPulseInterval - Inter-pulse interval in seconds (nonnegative).
    %   PulseDuration - Pulse width in seconds (nonnegative).
    %   PulseModeOn - Logical; true for active-high pulses, false for active-low.
    %   SamplingRate - Positive integer samples/second used by the device.
    %   timeout     - Positive scalar (seconds) to wait for device responses.
    %   port        - Serial port name (e.g., "COM3", "/dev/ttyACM0").
    %   baudrate    - Serial baud rate (e.g., 115200). Cannot be changed after connect.
    %
    % Properties (private set)
    %   S           - Serialport object handle created by connect().
    %
    % Typical workflow
    %   td = Trigduino("COM5",115200);
    %   td.connect();
    %   td.SamplingRate = 1000;      % Hz
    %   td.NPulses = 10;
    %   td.InterPulseInterval = 1e-3; % s
    %   td.PulseDuration = 5e-4;     % s
    %   td.trigger();                % start playback
    %
    % Notes
    %   * Units: IPI and PulseDuration are set in seconds on the MATLAB side;
    %     they are transmitted to the device in microseconds.
    %   * Handshakes: Setters send a command and assert that the device echoes
    %     the expected value.
    %   * Buffer writes: Setting Buffer pushes the entire array and checks that
    %     the device reports the received length.

    properties
        Buffer      (1,:) double {mustBeInteger,mustBeNonnegative,mustBeLessThanOrEqual(Buffer,4096)} = 0;
        NPulses     (1,1) double {mustBePositive,mustBeInteger,mustBeFinite} = 1;
        InterPulseInterval (1,1) double {mustBeNonnegative,mustBeFinite} = 1e-3; % seconds
        PulseDuration (1,1) double {mustBeNonnegative,mustBeFinite} = 1e-3; % seconds
        PulseModeOn  (1,1) logical = true;
        SamplingRate (1,1) double {mustBePositive,mustBeInteger,mustBeFinite} = 1000;

        Calibration  (1,1) double = 0;

        timeout     (1,1) double {mustBePositive} = 10;

        port        (1,1) string = "COM3";
        baudrate    (1,1) double = 115200;
    end

    properties (SetAccess = private)
        S
    end

    methods

        function obj = Trigduino(port,baudrate)
            % Trigduino Construct a controller instance.
            %
            % Syntax
            %   obj = Trigduino()
            %   obj = Trigduino(port)
            %   obj = Trigduino(port, baudrate)
            %
            % Inputs
            %   port     - (string) Serial port name. Defaults to stored property.
            %   baudrate - (double) Baud rate. Defaults to stored property.
            %
            % Notes
            %   If provided, inputs override the default property values prior
            %   to connection. Use connect() to open the serial link.
            if nargin >= 1 && ~isempty(port), obj.port = port; end
            if nargin == 2 && ~isempty(baudrate), obj.baudrate = baudrate; end
        end

        function delete(obj)
            % delete Destructor; closes and deletes the serialport handle.
            %
            % This method is called automatically when the object is cleared
            % or goes out of scope. It attempts to delete obj.S if it exists.
            delete(obj.S);
        end


        function info(obj)
            % info Print current Trigduino parameters and connection status.
            %
            %   Prints a formatted summary of key properties (connection, port,
            %   baudrate, sampling rate, pulse parameters, and buffer stats) to the
            %   Command Window.

            arguments
                obj
            end

            isConn = ~isempty(obj.S) && isvalid(obj.S);
            if isConn
                connStr = 'CONNECTED';
            else
                connStr = 'DISCONNECTED';
            end

            fprintf('=== Trigduino Status ===\n');
            fprintf('  Connection         : %s\n', connStr);
            fprintf('  Port / Baud        : %s / %d\n', string(obj.port), obj.baudrate);

            ipi_us = round(obj.InterPulseInterval * 1e6);
            dur_us = round(obj.PulseDuration * 1e6);
            if obj.InterPulseInterval > 0
                prf = 1/obj.InterPulseInterval;
            else
                prf = Inf;
            end

            fprintf('  SamplingRate (Hz)  : %d\n', obj.SamplingRate);
            fprintf('  NPulses            : %d\n', obj.NPulses);
            fprintf('  IPI                : %.6f s  (%d us)\n', obj.InterPulseInterval, ipi_us);
            fprintf('  PulseDuration      : %.6f s  (%d us)\n', obj.PulseDuration, dur_us);
            if obj.PulseModeOn
                modeStr = 'Active-High';
            else
                modeStr = 'Active-Low';
            end
            fprintf('  PulseMode          : %s\n', modeStr);

            if isfinite(prf)
                if prf >= 1
                    fprintf('  Pulse Repetition   : %.3f Hz\n', prf);
                else
                    fprintf('  Pulse Repetition   : %.3f Hz (%.1f s per pulse)\n', prf, 1/max(prf,eps));
                end
            else
                fprintf('  Pulse Repetition   : INF (IPI=0)\n');
            end

            n = numel(obj.Buffer);
            if n == 0
                fprintf('  Buffer             : (empty)\n');
            else
                bmin = min(obj.Buffer);
                bmax = max(obj.Buffer);
                k = min(n,10);
                pv = sprintf('%d ', obj.Buffer(1:k));
                pv = strtrim(pv);
                if n > k
                    pv = [pv ' ...'];
                end
                fprintf('  Buffer Length      : %d (min=%d, max=%d)\n', n, bmin, bmax);
                fprintf('  Buffer Preview     : %s\n', pv);
            end

            if isConn
                try
                    fprintf('  BytesAvailable     : %d\n', obj.S.NumBytesAvailable);
                catch
                    % ignore if serial object not fully initialized
                end
            end

            fprintf('=======================\n');

        end


        function set.baudrate(obj,br)
            % set.baudrate Set the baud rate before connecting.
            %
            % Input
            %   br - Numeric baud rate (e.g., 115200).
            %
            % Notes
            %   The baud rate cannot be changed after a connection is active.
            if ~isempty(obj.S) && isvalid(obj.S)
                warning('Can''t update the baudrate after a connection has been established')
            else
                obj.baudrate = br;
            end
        end

        function set.port(obj,port)
            % set.port Set the serial port name before connecting.
            %
            % Input
            %   port - Port identifier string (e.g., "COM3", "/dev/ttyACM0").
            %
            % Notes
            %   The port cannot be changed after a connection is active.
            if ~isempty(obj.S) && isvalid(obj.S)
                warning('Can''t update the port after a connection has been established')
            else
                obj.port = port;
            end
        end

        function connect(obj)
            % connect Open the serial connection and perform handshake.
            %
            % Description
            %   Creates a serialport object using the configured port and
            %   baudrate, waits briefly, and exchanges a one-byte handshake
            %   ('R') to confirm communication.
            %
            % Error behavior
            %   Throws an assertion if the serialport is invalid or the
            %   handshake fails within timeout.
            fprintf('Connecting to Arduino on port "%s"\n',obj.port)
            obj.S = serialport(obj.port,obj.baudrate);
            assert(isvalid(obj.S),'Trigduino:connect:FailedToConnect', ...
                'Failed to establish serial connection with the arduino')

            pause(1); % need to pause for a second or so to fully establish conneciton

            obj.write('R');

            s = obj.read;

            assert(s=='R','Trigduino:connect:FailedToConnect' , ...
                'Failed to handshake with to the arduino')
            disp('Connection established')
        end

        function trigger(obj)
            % trigger Start playback of the current buffer/parameters.
            %
            % Description
            %   Sends the 'T' command to the device. Playback begins
            %   immediately; no serial confirmation is expected.
            obj.write('T');

            % arduino should start buffer playback immediately and does not
            % confirm over serial port.
        end

        function set.Buffer(obj,buffer)
            % set.Buffer Set and write a new playback buffer to the device.
            %
            % Input
            %   buffer - Row vector of nonnegative integers (≤ 4096).
            %
            % Description
            %   Assigns the Buffer property and transmits the entire buffer
            %   to the device using write_buffer(), asserting the reported
            %   received length matches the input size.
            obj.Buffer = buffer;
            obj.write_buffer(buffer);
        end

        function set.SamplingRate(obj,fs)
            % set.SamplingRate Set device sampling rate (samples/second).
            %
            % Input
            %   fs - Positive integer sampling rate in Hz.
            %
            % Description
            %   Sends command 'S%d' and asserts that the echoed value equals fs.
            obj.SamplingRate = fs;
            obj.write('S%d',fs);
            [s,~,x] = obj.read;
            assert(fs==x, ...
                'Trigduino:SamplingRate:FailedToSetValue', ...
                'Sent S%d but received %s in response!',fs,s);
        end

        function set.NPulses(obj,n)
            % set.NPulses Set number of pulses per train.
            %
            % Input
            %   n - Positive integer count of pulses.
            %
            % Description
            %   Sends command 'N%d' and asserts that the echoed value equals n.
            obj.NPulses = n;
            obj.write('N%d',n);
            [s,~,x] = obj.read;
            assert(n==x, ...
                'Trigduino:NPulses:FailedToSetValue', ...
                'Sent N%d but received %s in response!',n,s);
        end

        %         function n = get.NPulses(obj)
        %             % get.NPulses Query NPulses from the device.
        %             %
        %             % Output
        %             %   n - Number of pulses per train reported by the device.
        %             obj.write('N');
        %             [~,~,n] = obj.read;
        %         end

        function set.InterPulseInterval(obj,ipi)
            % set.InterPulseInterval Set inter-pulse interval in seconds.
            %
            % Input
            %   ipi - Nonnegative scalar seconds.
            %
            % Description
            %   Converts to microseconds, sends 'I%d', and asserts echo.
            obj.InterPulseInterval = ipi; % set in seconds
            ipi = round((ipi + obj.Calibration)*1e6); % s -> microseconds
            obj.write('I%d',ipi);
            [s,~,i] = obj.read;
            assert(i==ipi, ...
                'Trigduino:InterPulseInterval:FailedToSetValue', ...
                'Sent I%d but received %s in response!',ipi,s);
        end



        function set.PulseDuration(obj,dur)
            % set.PulseDuration Set pulse width in seconds.
            %
            % Input
            %   dur - Nonnegative scalar seconds.
            %
            % Description
            %   Converts to microseconds, sends 'P%d', and asserts echo.
            obj.PulseDuration = dur; % set in seconds
            dur = round((dur + obj.Calibration)*1e6); % s -> microseconds
            obj.write('P%d',dur);
            [s,~,i] = obj.read;
            assert(i==dur, ...
                'Trigduino:InterPulseInterval:FailedToSetValue', ...
                'Sent I%d but received %s in response!',dur,s);
        end

        %         function n = get.InterPulseInterval(obj)
        %             % get.InterPulseInterval Query IPI from the device (microseconds).
        %             %
        %             % Output
        %             %   n - Inter-pulse interval reported by the device.
        %             obj.write('I');
        %             [~,~,n] = obj.read;
        %         end


        function set.PulseModeOn(obj,tf)
            obj.PulseModeOn = tf;
            obj.write('M%d',tf);
            [s,~,i] = obj.read;
            assert(i==tf, ...
                'Trigduino:PulseModeOn:FailedToSetValue', ...
                'Sent M%d but received %s in response!',tf,s);
        end

    end % methods (Access = public)



    methods (Access = protected)
        function [s,c,r] = read(obj)
            % read Read one line from the device with timeout.
            %
            % Outputs
            %   s - Full raw string (trimmed) returned by the device.
            %   c - First character of the response (command echo).
            %   r - Numeric value parsed from remaining characters, or NaN.
            %
            % Error behavior
            %   Asserts on timeout if no bytes are available within obj.timeout.
            starttime = clock;
            while obj.S.NumBytesAvailable == 0 ...
                    && etime(clock,starttime) < obj.timeout
                pause(0.2);
            end
            assert(etime(clock,starttime) < obj.timeout, ...
                'Triduino:read:Timeout', ...
                'Waited %d seconds for response, but received none.',obj.timeout)

            s = char(strip(obj.S.readline));
            c = s(1);
            if length(s) > 1
                r = str2num(s(2:end));
            else
                r = nan;
            end
        end

        function write(obj,varargin)
            % write Send a formatted command string to the device.
            %
            % Syntax
            %   write(obj, fmt, args...)
            %
            % Description
            %   Formats the input using sprintf(fmt, args{:}) and writes the
            %   resulting line over the serial connection.
            str = sprintf(varargin{:});
            obj.S.writeline(str);
        end

        function s = write_buffer(obj,buffer)
            % write_buffer Transmit an entire numeric buffer to the device.
            %
            % Input
            %   buffer - Row vector of nonnegative integers (≤ 4096).
            %
            % Output
            %   s - Raw response string from the device after write.
            %
            % Description
            %   Flushes the serial buffer, converts the vector to a compact
            %   bracket-free string, sends with command 'B ', and asserts
            %   that the device reports the expected element count.
            n = length(buffer);

            obj.S.flush;

            mstr = mat2str(buffer);
            mstr([1 end]) = [];
            obj.write('B %s',mstr);
            %             obj.write('B');
            %
            %             chnk = 10;
            %             for i = 1:chnk:n
            %                 idx = i:i+chnk;
            %                 idx(idx>n) = [];
            %                 mstr = mat2str(buffer(idx));
            %                 mstr([1 end]) = []; % remove [ ]
            %                 obj.write(mstr);
            %             end
            [s,~,x] = obj.read;
            assert(n == x,'Trigduino:write_buffer:BufferWriteFailed', ...
                'Sent buffer length of %d, but received %d in response!',n,x)

            disp('Updated buffer on Arduino')

        end

    end % methods (Access = protected)

end
