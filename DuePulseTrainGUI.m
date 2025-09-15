classdef DuePulseTrainGUI < handle
    % DuePulseTrainGUI
    % GUI to parameterize and trigger pulse trains on an Arduino Due.
    % Serial protocol:
    %   R | GO | STOP | COUNT
    %   CFG <pulse_us> <ipi_us> <pulses_per_train> <iti_us> <duty_pct> [pwm_hz] [ntrains]

    properties (Access = public)
        fig matlab.ui.Figure
        g   matlab.ui.container.GridLayout
        paramsPanel matlab.ui.container.Panel
        plotPanel   matlab.ui.container.Panel
        logPanel    matlab.ui.container.Panel

        % Tabs for parameterization modes (mode-specific only)
        paramTabs matlab.ui.container.TabGroup
        tabInterval matlab.ui.container.Tab
        tabRate matlab.ui.container.Tab

        % Axes
        axEnv matlab.graphics.axis.Axes
        axPWM matlab.graphics.axis.Axes

        % Intervals Tab controls (mode-specific)
        edPulse_ms matlab.ui.control.NumericEditField
        edIPI_ms   matlab.ui.control.NumericEditField
        edNPulses  matlab.ui.control.NumericEditField

        % Rate/Duration Tab controls (mode-specific)
        edPulse2_ms matlab.ui.control.NumericEditField
        edRate_Hz   matlab.ui.control.NumericEditField
        edTrainDur_s matlab.ui.control.NumericEditField

        % COMMON controls (outside tabs)
        edITI_s    matlab.ui.control.NumericEditField
        edDuty     matlab.ui.control.NumericEditField
        edPWM_Hz   matlab.ui.control.NumericEditField
        edNTrains  matlab.ui.control.NumericEditField % 0 = infinite

        % Buttons
        btnApply matlab.ui.control.Button
        btnGO    matlab.ui.control.Button
        btnSTOP  matlab.ui.control.Button
        btnPing  matlab.ui.control.Button

        % Status / Log / Count
        txtStatus matlab.ui.control.Label
        txtCount  matlab.ui.control.Label
        taLog     matlab.ui.control.TextArea

        % Menus
        mConn matlab.ui.container.Menu
        mPort matlab.ui.container.Menu
        mBaud matlab.ui.container.Menu
        mConnect matlab.ui.container.Menu
        mDisconnect matlab.ui.container.Menu
        mRefreshPorts matlab.ui.container.Menu

        % Serial state
        sp % serialport object (new MATLAB API). Set to [] when disconnected.
        port string = ""
        baud (1,1) double = 115200

        % Count tracking
        countTimer timer = timer.empty
        trainsDone double = 0
        trainsTarget double = 0
    end

    methods (Access = public)
        function self = DuePulseTrainGUI()
            % Constructor: build UI, initialize menus, draw default plot.
            self.buildUI;
            self.updateBaudChecks;
            self.rebuildPortMenu;
            self.updatePlot;
            self.updateCountLabel;
            if nargout == 0, clear self; end
        end

        function delete(self)
            % Ensure clean disconnect on destruction
            self.stopCountTracking;
            self.disconnect;
            if isvalid(self.fig)
                delete(self.fig);
            end
        end

        function connect(self, port, baud)
            % Open serial port with selected settings.
            arguments
                self
                port string = self.port
                baud (1,1) double {mustBePositive} = self.baud
            end
            if strlength(port) == 0
                self.setStatus("Select a COM port from Connection ▸ Port");
                return;
            end
            try
                if ~isempty(self.sp)
                    self.disconnect;
                end
                self.sp = serialport(port, baud, Timeout=5);
                % self.sp.Terminator = "CR/LF";  % robust with Arduino's CRLF prints
                flush(self.sp);  % clear any stale bytes before enabling callback
                configureCallback(self.sp, "terminator", @(~,~)self.cbSerialLine());
                self.port = port;
                self.baud = baud;
                self.updateBaudChecks;
                self.updatePortChecks;
                self.setStatus("Connected: " + port + " @ " + string(baud));
                self.log("[Connected]");
            catch ME
                self.sp = [];
                self.setStatus("Connect failed: " + ME.message);
                self.log("[ERROR] " + ME.message);
            end
        end

        function disconnect(self)
            % Close serial port and remove callback.
            try
                if ~isempty(self.sp)
                    try
                        configureCallback(self.sp, "off");
                    catch
                    end
                    self.sp = [];
                end
                self.stopCountTracking;
                self.setStatus("Disconnected");
                self.log("[Disconnected]");
            catch ME
                self.setStatus("Disconnect error: " + ME.message);
            end
        end

        function applyConfig(self)
            % Read UI values, send CFG, and update plot.
            p = self.getParams;
            self.updatePlot;
            self.sendCFG(p);
            self.trainsTarget = double(p.ntrains);
            self.updateCountLabel;
        end

        function go(self)
            % Send GO command and start count tracking.
            p = self.getParams;
            self.trainsTarget = double(p.ntrains);
            self.trainsDone = 0;
            self.updateCountLabel;
            self.sendLine("GO");
            self.startCountTracking;
            pause(0.05);
            self.pollCount; % kick off immediate COUNT
        end

        function stop(self)
            % Send STOP command and stop tracking.
            self.sendLine("STOP");
            self.pollCount; % fetch final count
            self.stopCountTracking;
        end

        function ping(self)
            % Send R (round-trip).
            self.sendLine("R");
        end
    end

    methods (Access = private)
        function buildUI(self)
            % Build figure and controls
            self.fig = uifigure(Name="Due Pulse Train GUI", Position=[100 100 1200 720]);
            self.g = uigridlayout(self.fig, [3 1]);
            self.g.RowHeight = {250, '1x', 140};
            self.g.ColumnWidth = {'1x'};

            % Connection menu
            self.mConn = uimenu(self.fig, 'Text', 'Connection');
            self.mPort = uimenu(self.mConn, 'Text', 'Port');
            self.mRefreshPorts = uimenu(self.mConn, 'Text', 'Refresh Ports', 'MenuSelectedFcn', @(~,~)self.rebuildPortMenu());
            self.mBaud = uimenu(self.mConn, 'Text', 'Baud Rate');
            for b = [9600 57600 115200 230400 460800 921600]
                uimenu(self.mBaud, 'Text', num2str(b), 'Tag', sprintf('BAUD_%d',b), ...
                    'MenuSelectedFcn', @(src,~)self.setBaudFromMenu(src));
            end
            self.mConnect = uimenu(self.mConn, 'Text', 'Connect', 'MenuSelectedFcn', @(~,~)self.connect());
            self.mDisconnect = uimenu(self.mConn, 'Text', 'Disconnect', 'MenuSelectedFcn', @(~,~)self.disconnect());

            % ---- Params panel with tabs (left) + common controls (right) and button row
            self.paramsPanel = uipanel(self.g, Title='Pulse Train Parameters');
            gpMain = uigridlayout(self.paramsPanel, [2 2]);
            gpMain.RowHeight = {'1x', 70};
            gpMain.ColumnWidth = {'1x', '1x'};

            % Tabs (mode-specific fields only) on the left
            self.paramTabs = uitabgroup(gpMain, SelectionChangedFcn=@(~,~)self.updatePlot());
            self.paramTabs.Layout.Row = 1; self.paramTabs.Layout.Column = 1;
            self.tabInterval = uitab(self.paramTabs, 'Title', 'Intervals');
            self.tabRate = uitab(self.paramTabs, 'Title', 'Rate / Duration');

            % Intervals tab grid (mode-specific only)
            gpA = uigridlayout(self.tabInterval, [2 3]);
            gpA.RowHeight = {30, 30};
            gpA.ColumnWidth = {140, 140, 160};
            uilabel(gpA, Text='Pulse (ms)');
            uilabel(gpA, Text='IPI (ms)');
            uilabel(gpA, Text='Pulses/Train');
            self.edPulse_ms = uieditfield(gpA, 'numeric', Limits=[0.001 Inf], Value=15);
            self.edIPI_ms   = uieditfield(gpA, 'numeric', Limits=[0 Inf], Value=35);
            self.edNPulses  = uieditfield(gpA, 'numeric', Limits=[1 Inf], RoundFractionalValues=true, Value=20);

            % Rate/Duration tab grid (mode-specific only)
            gpB = uigridlayout(self.tabRate, [2 3]);
            gpB.RowHeight = {30, 30};
            gpB.ColumnWidth = {140, 140, 160};
            uilabel(gpB, Text='Pulse (ms)');
            uilabel(gpB, Text='Rate (Hz)');
            uilabel(gpB, Text='Train Dur (s)');
            self.edPulse2_ms = uieditfield(gpB, 'numeric', Limits=[0.001 Inf], Value=15);
            self.edRate_Hz   = uieditfield(gpB, 'numeric', Limits=[0.001 Inf], Value=20);
            self.edTrainDur_s= uieditfield(gpB, 'numeric', Limits=[0.001 Inf], Value=1.0);

            % Common controls on the right (outside tabs)
            gpC = uigridlayout(gpMain, [2 4]);
            gpC.Layout.Row = 1; gpC.Layout.Column = 2;
            gpC.RowHeight = {24, 36};
            gpC.ColumnWidth = {110, 110, 110, 120};
            uilabel(gpC, Text='ITI (s)');
            uilabel(gpC, Text='Duty (%)');
            uilabel(gpC, Text='PWM (Hz)');
            uilabel(gpC, Text='Trains (0=∞)');
            self.edITI_s   = uieditfield(gpC, 'numeric', Limits=[0 Inf], Value=5);
            self.edDuty    = uieditfield(gpC, 'numeric', Limits=[0 100], Value=100);
            self.edPWM_Hz  = uieditfield(gpC, 'numeric', Limits=[1 Inf], Value=10000);
            self.edNTrains = uieditfield(gpC, 'numeric', Limits=[0 Inf], RoundFractionalValues=true, Value=0);

            % Buttons row spanning both columns
            gb = uigridlayout(gpMain, [1 6]);
            gb.Layout.Row = 2; gb.Layout.Column = [1 2];
            gb.ColumnWidth = {150, 100, 100, 100, 300, '1x'};
            gb.RowHeight = {60};
            self.btnApply = uibutton(gb, 'Text','Apply Config', 'ButtonPushedFcn', @(~,~)self.applyConfig());
            self.btnGO    = uibutton(gb, 'Text','GO',          'ButtonPushedFcn', @(~,~)self.go());
            self.btnSTOP  = uibutton(gb, 'Text','STOP',        'ButtonPushedFcn', @(~,~)self.stop());
            self.btnPing  = uibutton(gb, 'Text','Ping (R)',    'ButtonPushedFcn', @(~,~)self.ping());
            self.txtCount = uilabel(gb, Text='Trains: 0 / ∞', FontWeight='bold', FontSize=18);
            self.txtStatus = uilabel(gb, Text='Disconnected', FontWeight='bold');

            % Button styles
            self.btnApply.BackgroundColor = [0.85 0.85 0.95];
            self.btnGO.BackgroundColor    = [0.75 0.93 0.76];
            self.btnSTOP.BackgroundColor  = [0.96 0.76 0.76];
            self.btnPing.BackgroundColor  = [0.91 0.91 0.91];

            % Any value change -> update plot
            set([self.edPulse_ms,self.edIPI_ms,self.edNPulses, ...
                 self.edPulse2_ms,self.edRate_Hz,self.edTrainDur_s, ...
                 self.edITI_s,self.edDuty,self.edPWM_Hz,self.edNTrains], ...
                'ValueChangedFcn', @(~,~)self.updatePlot());

            % ---- Plot panel
            self.plotPanel = uipanel(self.g, Title='Visualization');
            gp2 = uigridlayout(self.plotPanel, [1 2]);
            gp2.ColumnWidth = {'1x','1x'};
            self.axEnv = uiaxes(gp2);
            title(self.axEnv, 'Train Envelope (Windows)');
            xlabel(self.axEnv, 'Time (ms)'); ylabel(self.axEnv, 'Window (0/1)');
            grid(self.axEnv, 'on');
            self.axPWM = uiaxes(gp2);
            title(self.axPWM, 'PWM within a Pulse (zoom)');
            xlabel(self.axPWM, 'Time within pulse (µs)'); ylabel(self.axPWM, 'Level');
            grid(self.axPWM, 'on');

            % ---- Log panel
            self.logPanel = uipanel(self.g, Title='Device Log');
            gl = uigridlayout(self.logPanel, [1 1]);
            self.taLog = uitextarea(gl, Value={''});
            self.taLog.Editable = 'off';
        end

        function rebuildPortMenu(self)
            % Populate Port submenu with available ports
            delete(get(self.mPort,'Children'));
            ports = serialportlist("available");
            if isempty(ports)
                uimenu(self.mPort, 'Text','<no ports>', 'Enable','off');
            else
                for k = 1:numel(ports)
                    uimenu(self.mPort, 'Text', ports(k), 'Tag', "PORT_" + ports(k), ...
                        'MenuSelectedFcn', @(src,~)self.setPortFromMenu(src));
                end
            end
            self.updatePortChecks;
        end

        function setPortFromMenu(self, src)
            self.port = string(src.Text);
            self.updatePortChecks;
        end

        function setBaudFromMenu(self, src)
            self.baud = str2double(src.Text);
            self.updateBaudChecks;
        end

        function updatePortChecks(self)
            kids = get(self.mPort,'Children');
            for i = 1:numel(kids)
                if startsWith(string(kids(i).Tag),"PORT_")
                    kids(i).Checked = strcmp(string(kids(i).Text), self.port);
                end
            end
        end

        function updateBaudChecks(self)
            kids = get(self.mBaud,'Children');
            for i = 1:numel(kids)
                if startsWith(string(kids(i).Tag),"BAUD_")
                    kids(i).Checked = str2double(kids(i).Text) == self.baud;
                end
            end
        end

        function p = getParams(self)
            % Gather parameters from UI and convert to device units (µs/Hz/%/count)
            p = struct;
            if self.paramTabs.SelectedTab == self.tabInterval
                p.pulse_us = max(1, round(self.edPulse_ms.Value * 1000));
                p.ipi_us   = max(0, round(self.edIPI_ms.Value  * 1000));
                p.n        = max(1, round(self.edNPulses.Value));
            else
                p.pulse_us = max(1, round(self.edPulse2_ms.Value * 1000));
                rate_hz    = max(0.001, self.edRate_Hz.Value);
                period_us  = max(1, round(1e6 / rate_hz));
                p.ipi_us   = max(0, period_us - p.pulse_us);
                train_us   = max(1, round(self.edTrainDur_s.Value * 1e6));
                if train_us <= p.pulse_us
                    p.n = 1;
                else
                    p.n = floor((train_us - p.pulse_us) / period_us) + 1;
                    p.n = max(1, p.n);
                end
            end
            p.iti_us   = max(0, round(self.edITI_s.Value   * 1e6));
            p.duty_pct = min(100, max(0, round(self.edDuty.Value)));
            p.pwm_hz   = max(1, round(self.edPWM_Hz.Value));
            p.ntrains  = max(0, round(self.edNTrains.Value));
        end

        function updatePlot(self)
            p = self.getParams;
            [tx, yx, Ttrain_ms] = self.makeEnvelopeStairs(p);
            cla(self.axEnv);
            stairs(self.axEnv, tx, yx, 'LineWidth',2);
            xlim(self.axEnv, [0, max(tx)]);
            ylim(self.axEnv, [-0.1, 1.1]);
            txt = sprintf('Train length = %.3f s', Ttrain_ms/1000);
            if p.ntrains > 0
                txt = sprintf('%s, Trains per GO = %d', txt, p.ntrains);
            else
                txt = sprintf('%s, Trains per GO = ∞', txt);
            end
            self.axEnv.Title.String = ['Train Envelope (Windows) — ' txt];
            [tpwm, ypwm] = self.makePWMStairs(p);
            cla(self.axPWM);
            stairs(self.axPWM, tpwm, ypwm, 'LineWidth',2);
            xlim(self.axPWM, [0, max(tpwm)]);
            ylim(self.axPWM, [-0.1, 1.1]);
        end

        function [tx, yx, Ttrain_ms] = makeEnvelopeStairs(self, p)
            pulse_ms = p.pulse_us/1000;
            ipi_ms   = p.ipi_us/1000;
            t = 0; tx = 0; yx = 0; %#ok<NASGU>
            tx = 0; yx = 0;
            tx(1) = 0; yx(1) = 0; %#ok<AGROW>
            for k = 1:p.n
                t_on  = t;
                t_off = t + pulse_ms;
                tx(end+1) = t_on;  yx(end+1) = 0; %#ok<AGROW>
                tx(end+1) = t_on;  yx(end+1) = 1; %#ok<AGROW>
                tx(end+1) = t_off; yx(end+1) = 1; %#ok<AGROW>
                tx(end+1) = t_off; yx(end+1) = 0; %#ok<AGROW>
                if k < p.n
                    t = t_off + ipi_ms;
                else
                    t = t_off;
                end
            end
            Ttrain_ms = t;
        end

        function [tpwm, ypwm] = makePWMStairs(self, p)
            Tper = 1e6 / p.pwm_hz;
            ton  = Tper * (p.duty_pct/100);
            toff = Tper - ton;
            if p.duty_pct <= 0
                ton = 0; toff = Tper;
            elseif p.duty_pct >= 100
                ton = Tper; toff = 0;
            end
            maxwin = min(p.pulse_us, 10*Tper);
            tpwm = 0; ypwm = 0; %#ok<NASGU>
            tpwm = 0; ypwm = 0;
            t = 0; level = 0; %#ok<NASGU>
            level = 0;
            while t < maxwin
                if toff > 0
                    tpwm(end+1) = t;   ypwm(end+1) = 0; %#ok<AGROW>
                    tpwm(end+1) = t+toff; ypwm(end+1) = 0; %#ok<AGROW>
                    t = t + toff;
                end
                if t >= maxwin, break, end
                if ton > 0
                    tpwm(end+1) = t;   ypwm(end+1) = 1; %#ok<AGROW>
                    tpwm(end+1) = min(t+ton, maxwin); ypwm(end+1) = 1; %#ok<AGROW>
                    t = t + ton;
                end
            end
            if tpwm(1) ~= 0
                tpwm = [0, tpwm]; ypwm = [0, ypwm];
            end
        end

        function sendCFG(self, p)
            cmd = sprintf('CFG %u %u %u %u %u %u %u', p.pulse_us, p.ipi_us, p.n, p.iti_us, p.duty_pct, p.pwm_hz, p.ntrains);
            self.sendLine(cmd);
        end

        function sendLine(self, line)
            if isempty(self.sp)
                self.setStatus("Not connected");
                return;
            end
            try
                writeline(self.sp, line);
                self.log("> " + string(line));
            catch ME
                self.setStatus("Write failed: " + ME.message);
                self.log("[ERROR] " + ME.message);
            end
        end

        function cbSerialLine(self)
            self.drainLines;
        end

        function drainLines(self)
            try
                while ~isempty(self.sp) && self.sp.NumBytesAvailable > 0
                    ln = string(strtrim(readline(self.sp)));
                    if strlength(ln) > 0
                        if startsWith(ln, "COUNT=")
                            val = str2double(extractAfter(ln, "COUNT="));
                            if ~isnan(val)
                                self.trainsDone = val;
                                self.updateCountLabel;
                                if self.trainsTarget > 0 && self.trainsDone >= self.trainsTarget
                                    self.stopCountTracking;
                                end
                            end
                        else
                            self.log(ln);
                            self.setStatus(ln);
                        end
                    end
                end
            catch
            end
        end

        function startCountTracking(self)
            self.stopCountTracking;
            try
                self.countTimer = timer('ExecutionMode','fixedSpacing','Period',0.5, ...
                    'TimerFcn', @(~,~)self.pollCount(), 'BusyMode','drop');
                start(self.countTimer);
            catch
            end
        end

        function stopCountTracking(self)
            try
                if ~isempty(self.countTimer) && isvalid(self.countTimer)
                    stop(self.countTimer);
                    delete(self.countTimer);
                end
            catch
            end
            self.countTimer = timer.empty;
        end

        function pollCount(self)
            if isempty(self.sp)
                return;
            end
            try
                writeline(self.sp, 'COUNT'); % silent poll
            catch
            end
            pause(0.01);
            self.drainLines; % force update if callback timing jitters
        end

        function setStatus(self, msg)
            if isvalid(self.txtStatus)
                self.txtStatus.Text = char(msg);
            end
        end

        function updateCountLabel(self)
            if ~isvalid(self.txtCount)
                return;
            end
            if self.trainsTarget > 0
                self.txtCount.Text = sprintf('Trains: %d / %d', self.trainsDone, self.trainsTarget);
            else
                self.txtCount.Text = sprintf('Trains: %d / ∞', self.trainsDone);
            end
        end

        function log(self, msg)
            if ~isvalid(self.taLog), return, end
            v = self.taLog.Value;
            if ischar(v) || isstring(v)
                v = cellstr(v);
            end
            v{end+1} = char(msg);
            if numel(v) > 500
                v = v(end-500:end);
            end
            self.taLog.Value = v;
            drawnow limitrate;
        end
    end
end
