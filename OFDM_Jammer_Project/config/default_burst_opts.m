function burst = default_burst_opts()
% default_burst_opts  Default burst-orchestration parameters used by
% tx_burst_console / rx_burst_console.
%
%   These knobs sit on top of load_parameters().  They govern WHEN the
%   TX channel is on and WHEN the jammer fires, which is orthogonal to
%   the existing mode_registry (which decides WHAT jammer waveform to
%   build).  Override any subset by passing a struct as the burstOpts
%   argument, e.g.
%       opts.jammerPattern = 'single_shot';
%       opts.singleShotBurst = 5;
%       tx_burst_console(8, opts);
%
%   All timing units are in FRAMES (one frame = length(real_frame)/fs s).
%   Convert from seconds via the spec/tx rate if you prefer wall-time
%   thinking: framesPerSec = params.tx.fs / refs.frame_len.

    % --- TX duty cycle -------------------------------------------------
    burst.framesPerBurst    = 100;     % TX-on portion of one period
    burst.txPeriodFrames    = 250;     % full period; off = period - on
    burst.numBursts         = 20;      % stop after this many TX bursts
                                       %   (override with runSeconds if 0)
    burst.runSeconds        = 0;       % if > 0, takes precedence over numBursts

    % --- TX pre-burst silence (RX warm-up window) ---------------------
    burst.delayBeforeStartSec = 0;     % seconds of zeros before first burst;
                                       %   lets RX finish calib uncontaminated

    % --- Jammer firing pattern ----------------------------------------
    %   'continuous'   - jammer always on (legacy behavior)
    %   'periodic'     - jammer on for jamOnFrames per jamPeriodFrames
    %   'random'       - PER-FRAME Bernoulli jamRandomProb (twitchy fine-
    %                    grain noise; granularity = one frame ~ 2.3 ms)
    %   'random_bursts'- PER-BURST Bernoulli jamRandomProb; selected
    %                    bursts get fully jammed during their TX-on
    %                    window, rest go clean (closer to "irregular
    %                    real-world jammer that picks targets")
    %   'single_shot'  - fire only during burst index singleShotBurst,
    %                    to demo a single precisely-timed strike
    burst.jammerPattern     = 'continuous';

    % --- 'periodic' tunables ------------------------------------------
    burst.jamOnFrames       = 100;
    burst.jamPeriodFrames   = 200;
    burst.alignJamToTx      = false;   % true: jammer mirrors TX duty
                                       %   (fires iff TX on)

    % --- 'random' / 'random_bursts' tunables --------------------------
    burst.jamRandomProb     = 0.30;    % per-frame or per-burst fire prob
    burst.jamRandomSeed     = 0;       % 0 = no fixed seed

    % --- 'single_shot' tunables ---------------------------------------
    burst.singleShotBurst   = 5;       % 1-based burst index to strike
    burst.singleShotJamOn   = 'tx_on'; % 'tx_on' (mirror burst window)
                                       % | 'full_period' (also off-window)

    % --- RX-side reporting --------------------------------------------
    burst.rxFramesPerReport = 100;     % bucket size for per-burst stats
                                       %   (RX uses detected-frame count,
                                       %    not TX wall-clock)
    burst.rxVerbose         = true;    % print per-burst summary lines

    % --- RX auto-stop -------------------------------------------------
    burst.rxAutoStopIdleSec = 0;       % >0: stop if no detection for
                                       %   this many seconds AFTER first
                                       %   detection.  Pairs nicely with
                                       %   TX numBursts mode so RX exits
                                       %   when TX runs out of bursts.

    % --- RX infers which TX burst each detected frame belongs to ------
    burst.inferTxBurstOnRx  = true;    % use inter-frame gap > 0.5 * TX
                                       %   off-window to detect a new TX
                                       %   burst boundary.  Needs
                                       %   framesPerBurst + txPeriodFrames
                                       %   matching TX side.

    % --- RX .mat log (offline plotting) -------------------------------
    burst.logToMat          = false;
    burst.logMatPath        = '';      % default: auto-name with timestamp
end
