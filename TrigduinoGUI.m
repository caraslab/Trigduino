classdef TrigduinoGUI < handle
    
    properties (SetObservable, AbortSet)
       BufferShapeFcn (1,1) = @rectwin;
       
    end
    
    properties (SetAccess = private)
        Trigduino
        
        triggerCount = 0;
    end
    
    properties (SetAccess = private,Hidden)
        figure
        parent
        handles
    end
    
    properties (Dependent,Hidden)
        timevec
    end
    
    properties (Constant)
        DACBits = 12;
    end
    
    methods
        function obj = TrigduinoGUI(port,baudrate)
            dflts = {[],[]};
            if nargin > 0, dflts{1} = port; end
            if nargin > 1, dflts{2} = baudrate; end
            
            obj.connect(dflts{:});
            obj.create;
        end
        
        function delete(obj)
%             setpref('TigduinoGUI','FigurePosition',obj.figure.Position);
%             close(obj.figure);
        end
        
        function connect(obj,port,baudrate)

            dflts = {[],[]};
            if nargin > 1, dflts{1} = port; end
            if nargin > 2, dflts{2} = baudrate; end
            
            obj.Trigduino = Trigduino(dflts{:}); %#ok<CPROPLC>
            obj.Trigduino.connect;
        end
        
        function t = get.timevec(obj)
            n = length(obj.Trigduino.Buffer);
            t = (0:n-1)./obj.Trigduino.SamplingRate;
        end
    end
    
    methods (Access = protected)
        
        function update_buffer(obj,src,evnt)
            n = obj.handles.numBufferLength.Value;
            s = obj.handles.txtBufferShape.Value;
            
            w = which(s);
            if isempty(w)
                uialert(obj.figure,'Invalid function or not found on Matlab''s path.', ...
                    'Trigduino','Icon','error','Modal',true);
                obj.handles.txtBufferShape.Value = func2str(obj.BufferShapeFcn);
                return
            end
            
            obj.BufferShapeFcn = str2func(s);
            
            w = obj.BufferShapeFcn(n);
            
            w = 2^obj.DACBits .* w(:)';
            
            w = round(w);
            
            obj.Trigduino.Buffer = w;
            
            obj.update_plots;
        end
        
        function update_parameter(obj,src,evnt,prop)
            
            try
                obj.Trigduino.(prop) = evnt.Value;
                obj.update_plots;
                
            catch
                obj.Trigduino.(prop) = evnt.PreviousValue;
                uialert(obj.figure,'Invalid value', ...
                    'Trigduino','Icon','error','Modal',true);
            end
        end
        
        function tf = isconnected(obj,showalert)
            if nargin < 2, showalert = true; end
            tf = ~isempty(obj.Trigduino) && isvalid(obj.Trigduino);
            
            if showalert && ~tf
                uialert(obj.figure,'Not connected to arduino.', ...
                    'Trigduino','Icon','error','Modal',true);
            end
        end
        
        function update_plots(obj)
            
            tvec = obj.timevec;
            buffer = obj.Trigduino.Buffer;
            
            
            h = obj.handles.lineStimSegment;
            h.XData = tvec;
            h.YData = buffer;
            
            ax = obj.handles.axStimSegment;
            if length(tvec) > 1
                axis(ax,[tvec([1 end]) 0 1.1*max(buffer)]);
            end
            
            
            
            
            nPulses = obj.Trigduino.NPulses;
            Fs = obj.Trigduino.SamplingRate;
            ipi = obj.Trigduino.InterPulseInterval ./ 1000; % s -> ms
            buffer = [buffer zeros(1,round(ipi./Fs))];
            buffer = repmat(buffer,1,nPulses);
            tvec = (0:length(buffer)-1)./Fs;
            
            h = obj.handles.lineStimTrain;
            h.XData = tvec;
            h.YData = buffer;
            
            ax = obj.handles.axStimTrain;
            if length(tvec) > 1
                axis(ax,[tvec([1 end]) 0 1.1*max(buffer)]);
            end
        end
        
        function trigger(obj,src,evnt)
            if ~obj.isconnected, return; end
            
            try
                obj.Trigduino.trigger;
                obj.triggerCount = obj.triggerCount + 1;
                obj.handles.lblTriggerCount.Text = num2str(obj.triggerCount,'%d');
            catch
            end
        end
        
        function create(obj)
            
            if isempty(obj.parent)
                pos = getpref('TrigduinoGUI','FigurePosition',[400 250 700 350]);
                obj.parent = uifigure;
                obj.parent.Position = pos;
                obj.parent.CreateFcn = {@movegui,'onscreen'};
                obj.parent.Color = 'w';
            end
            
            obj.figure = ancestor(obj.parent,'figure');
            
            g = uigridlayout(obj.parent);
            g.ColumnWidth = {140,'1x'};
            g.RowHeight = {'1x','1x'};
            
            obj.handles.MainGrid = g;
            
            
            pg = uigridlayout(g);
            pg.ColumnWidth = {'1x'};
            pg.RowHeight = [repmat({20},1,10),{30,'1x'}];
            pg.Layout.Column = 1;
            pg.Layout.Row = [1 2];
            pg.Padding = [0 0 0 0];
            pg.RowSpacing = 2;
            obj.handles.PropertiesGrid = pg;
            
            h = uilabel(pg);
            h.Text = '# Samples per Pulse';
            obj.handles.lblPulseSamples = h;
            
            h = uieditfield(pg,'numeric');
            h.Limits = [1 1000];
            h.LowerLimitInclusive = 'on';
            h.UpperLimitInclusive = 'on';
            h.RoundFractionalValues = 'on';
            h.Value = 10;
            h.ValueDisplayFormat = '%d';
            h.ValueChangedFcn = @obj.update_buffer;
            obj.handles.numBufferLength = h;
            
            
            h = uilabel(pg);
            h.Text = 'Buffer Shape Fcn';
            obj.handles.lblBufferShape = h;
            
            h = uieditfield(pg);
            h.Value = 'rectwin';
            h.HorizontalAlignment = 'right';
            h.ValueChangedFcn = @obj.update_buffer;
            obj.handles.txtBufferShape = h;
            
            h = uilabel(pg);
            h.Text = 'Sampling Rate';
            obj.handles.lblSamplingRate = h;
            
            h = uieditfield(pg,'numeric');
            h.Limits = [1 1000];
            h.LowerLimitInclusive = 'on';
            h.UpperLimitInclusive = 'on';
            h.RoundFractionalValues = 'on';
            h.Value = 10;
            h.ValueDisplayFormat = '%d Hz';
            h.ValueChangedFcn = {@obj.update_parameter,'SamplingRate'};
            obj.handles.numSamplingRate = h;
            
            h = uilabel(pg);
            h.Text = 'Inter-Pulse Interval';
            obj.handles.lblIPI = h;
            
            h = uieditfield(pg,'numeric');
            h.Limits = [0 1000];
            h.LowerLimitInclusive = 'on';
            h.UpperLimitInclusive = 'on';
            h.Value = 0;
            h.ValueDisplayFormat = '%.1f ms';
            h.ValueChangedFcn = {@obj.update_parameter,'InterPulseInterval'};
            obj.handles.numIPI = h;
            
            h = uilabel(pg);
            h.Text = '# Pulses';
            obj.handles.lbl = h;
            
            h = uieditfield(pg,'numeric');
            h.Limits = [1 1e6];
            h.LowerLimitInclusive = 'on';
            h.UpperLimitInclusive = 'on';
            h.RoundFractionalValues = 'on';
            h.Value = 10;
            h.ValueDisplayFormat = '%d';
            h.ValueChangedFcn = {@obj.update_parameter,'NPulses'};
            obj.handles.numPulses = h;
            
            
            h = uilabel(pg);
            h.Text = '0';
            h.Tag = 'Trigger Count';
            h.FontWeight = 'bold';
            h.FontSize = 16;
            h.HorizontalAlignment = 'center';
            obj.handles.lblTriggerCount = h;
            
            h = uibutton(pg);
            h.Text = 'Trigger';
            h.Tag = 'Trigger';
            h.FontWeight = 'bold';
            h.FontSize = 16;
            h.BackgroundColor = '#ff7a73';
            h.ButtonPushedFcn = @obj.trigger;
            obj.handles.btnTrigger = h;
            
            
            % --- axes ---
            h = uiaxes(g,'Tag','StimSegment');
            h.Layout.Column = 2;
            h.Layout.Row = 1;
            h.BackgroundColor = 'w';
            h.XGrid = 'on';
            h.YGrid = 'on';
            h.Title.String = 'Segment';
            obj.handles.axStimSegment = h;
            
            h = line(h,nan,nan);
            h.Color = 'k';
            h.LineWidth = 2;
            obj.handles.lineStimSegment = h;
            
            h = uiaxes(g,'Tag','StimTrain');
            h.Layout.Column = 2;
            h.Layout.Row = 2;
            h.BackgroundColor = 'w';
            h.XGrid = 'on';
            h.YGrid = 'on';
            h.Title.String = 'Stimulus';
            obj.handles.axStimTrain = h;
            
            h = line(h,nan,nan);
            h.Color = 'k';
            h.LineWidth = 2;
            obj.handles.lineStimTrain = h;
            
            
            h = findobj(obj.parent,'-property','FontName');
            set(h,'FontName','Consolas');
            
            
            obj.update_plots;
        end
    end
    
end

