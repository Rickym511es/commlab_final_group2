function params = load_parameters_3node()
% load_parameters_3node  Single source of truth for the 3-node USRP topology.
%
%   Models the realistic case "A transmits to B, attacked by an unknown C"
%   on THREE separate N210 radios:
%       A (USRP2) -> legitimate continuous OFDM TX        (params.A)
%       B (USRP1) -> victim receiver                       (params.B)
%       C (USRP3) -> reactive jammer, sense-then-jam (TDD) (params.C)
%
%   Waveform spec / attack tunables / detector thresholds are REUSED from
%   the 2-node OFDM_Jammer_Project/config/load_parameters.m so the two
%   projects can never drift on the things that must match (FFT/CP/QAM/
%   pilots/seed). Only the device + topology layer is defined here.
%
%   IMPORTANT: every node must agree on params.rf.fc and params.rf.fs.
%   Set the four ipAddress fields to your actual radios before running.

    base = load_parameters();          % from OFDM_Jammer_Project (on path)

    % --- shared RF invariants (all three nodes MUST match) -------------
    rf.fc          = 885e6;
    rf.fs          = 1e6;
    rf.masterClock = 100e6;            % N210 fixed master clock
    rf.interp      = rf.masterClock / rf.fs;   % N210 TX interpolation
    rf.deci        = rf.masterClock / rf.fs;   % N210 RX decimation
    rf.spec        = base.spec;        % OFDM/frame spec (reused)
    params.rf = rf;

    plat = 'N200/N210/USRP2';

    % --- Node A: legitimate transmitter (USRP2) ------------------------
    A.ipAddress = '192.168.10.3';
    A.platform  = plat;
    A.gain      = 25;
    A.interp    = rf.interp;
    A.liveDisplay = true;
    A.displayEvery = 50;
    params.A = A;

    % --- Node B: victim receiver (USRP1) -------------------------------
    B.ipAddress      = '192.168.10.2';
    B.platform       = plat;
    B.gain           = 30;
    B.samplesPerFrame= 8192;
    B.deci           = rf.deci;
    B.displayEvery   = 5;
    params.B = B;

    % --- Node C: reactive jammer (USRP3), ONE radio doing TX+RX (TDD) --
    %   C.tx and C.rx share the same ipAddress (same physical N210).
    C.tx.ipAddress = '192.168.10.4';
    C.tx.platform  = plat;
    C.tx.gain      = 20;               % primary JSR knob at B (jamGain)
    C.tx.interp    = rf.interp;

    C.rx.ipAddress      = '192.168.10.4';
    C.rx.platform       = plat;
    C.rx.gain           = 30;
    C.rx.samplesPerFrame= 8192;
    C.rx.deci           = rf.deci;

    % reactive behavior knobs
    C.react.reactive      = true;      % false -> periodic/continuous fallback
    C.react.senseReads    = 3;         % rx() captures per sense window
    C.react.detectThresh  = base.detect.autocorrThreshold;  % A-busy threshold
    C.react.energyThresh  = 0;         % >0: also require rms(data) over this
    C.react.jamBursts     = 200;       % tx frames streamed per trigger
    C.react.jammerMode    = 8;         % attack id 0..12 (8 = broadband)
    C.react.jammerType    = 2;         % 1 noise / 2 structured (per mode)
    C.react.power         = 1;         % digital scale into normalize_jammer
    C.react.alignToFrame  = true;      % offset tx by detected frame_start
    % non-reactive (reactive=false) duty cycle, in frames
    C.react.dutyOnFrames    = 200;
    C.react.dutyPeriodFrames= 400;
    params.C = C;

    % --- reused: attack tunables, detector thresholds ------------------
    params.knob   = base.knob;
    params.detect = base.detect;

    % --- monitor timing (B + C session length) -------------------------
    params.monitor.runSeconds   = 480;
    params.monitor.calibSeconds = 6;
    params.monitor.displayEvery = 5;
end
