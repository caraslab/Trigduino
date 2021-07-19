classdef Trigduino < handle
    
    properties
        Buffer      (1,:) double {mustBeInteger,mustBeNonnegative,mustBeLessThanOrEqual(Buffer,4096)} = 0;
        NPulses     (1,1) double {mustBePositive,mustBeInteger,mustBeFinite} = 1;
        InterPulseInterval (1,1) double {mustBeNonnegative,mustBeFinite} = 1e-3; % seconds
        SamplingRate (1,1) double {mustBePositive,mustBeInteger,mustBeFinite} = 1000;
        
        timeout     (1,1) double {mustBePositive} = 10;
        
        port        (1,1) string = "COM3";
        baudrate    (1,1) double = 115200;
    end
    
    properties (SetAccess = private)
        S
    end
    
    methods
        
        function obj = Trigduino(port,baudrate)
            if nargin >= 1 && ~isempty(port), obj.port = port; end
            if nargin == 2 && ~isempty(baudrate), obj.baudrate = baudrate; end
        end
        
        function delete(obj)
            delete(obj.S);
        end
        
        function set.baudrate(obj,br)
            if ~isempty(obj.S) && isvalid(obj.S)
                warning('Can''t update the baudrate after a connection has been established')
            else
                obj.baudrate = br;
            end
        end
        
        function set.port(obj,port)
            if ~isempty(obj.S) && isvalid(obj.S)
                warning('Can''t update the port after a connection has been established')
            else
                obj.port = port;
            end
        end
        
        
        
        function connect(obj)
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
            obj.write('T');
            
            % arduino should start buffer playback immediately and does not
            % confirm over serial port.
        end
        
        function set.Buffer(obj,buffer)
            obj.Buffer = buffer;
            obj.write_buffer(buffer);
        end
        
        function set.SamplingRate(obj,fs)
            obj.SamplingRate = fs;
            obj.write('S%d',fs);
            [s,~,x] = obj.read;
            assert(fs==x, ...
                'Trigduino:SamplingRate:FailedToSetValue', ...
                'Sent S%d but received %s in response!',fs,s);
        end
        
        function set.NPulses(obj,n)
            obj.NPulses = n;
            obj.write('N%d',n);
            [s,~,x] = obj.read;
            assert(n==x, ...
                'Trigduino:NPulses:FailedToSetValue', ...
                'Sent N%d but received %s in response!',n,s);
        end
        
%         function n = get.NPulses(obj)
%             obj.write('N');
%             [~,~,n] = obj.read;
%         end
        
        function set.InterPulseInterval(obj,ipi)
            obj.InterPulseInterval = ipi; % set in seconds            
            ipi = round(ipi*1e6); % s -> microseconds
            obj.write('I%d',ipi);
            [s,~,i] = obj.read;
            assert(i==ipi, ...
                'Trigduino:InterPulseInterval:FailedToSetValue', ...
                'Sent I%d but received %s in response!',ipi,s);
        end
        
%         function n = get.InterPulseInterval(obj)
%             obj.write('I');
%             [~,~,n] = obj.read;
%         end

    end % methods (Access = public)
    
    
    
    methods (Access = protected)
        function [s,c,r] = read(obj)
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
            str = sprintf(varargin{:});
            obj.S.writeline(str);
        end
        
        function s = write_buffer(obj,buffer)
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

