function run_tx_burst(params, burst, phase, tx, uiCtx)
% run_tx_burst  TX while-loop with burst gating.  Single jammer mode
% throughout; jammer waveform is built once, then per-frame gated by the
% pattern in burst.jammerPattern.  TX channel itself is duty-cycled at
% (framesPerBurst on, txPeriodFrames-framesPerBurst off).
%
% Stops at min(numBursts*txPeriodFrames frames, runSeconds wall-time) -
% whichever the user enabled.  If burst.runSeconds > 0 it takes
% precedence over numBursts.
%
% Optional 5th arg uiCtx exposes hooks for UI integration:
%   uiCtx.shouldStop  : function handle, no args, returns logical.
%                       Loop checks each iteration and breaks if true.
%   uiCtx.onProgress  : function handle taking (iter, burstIdx, underrunCnt).
%                       Called every iteration so UI can throttle itself.
% Pass [] or omit for non-UI use.

    if nargin < 5 || isempty(uiCtx)
        uiCtx = struct('shouldStop', @() false, ...
                       'onProgress', @(varargin) []);
    end

    validate_burst(burst);

    spec = params.spec;
    [real_frame, info, ~] = build_frame(spec);
    tx_rms   = rms(real_frame);
    frameLen = length(real_frame);
    zero_ch  = zeros(frameLen, 1);

    % --- build jammer once (single mode, fixed waveform) ---
    if phase.mode == 0
        jammer = zero_ch;
        jam_available = false;
    else
        jammer = phase.descriptor.build(phase.type, phase.bw_idx, ...
                                        real_frame, info, ...
                                        params.tx.fs, params.knob);
        if phase.type ~= 0
            jammer = normalize_jammer(jammer, real_frame, phase.type, params.knob);
        end
        jpk = max(abs(jammer));
        if jpk > 0.95
            jammer = jammer * (0.95 / jpk);
            fprintf('  (jammer peak %.2f > 0.95, scaling)\n', jpk);
        end
        jam_available = true;
    end

    % --- stop condition ---
    framesPerSec = params.tx.fs / frameLen;
    if burst.runSeconds > 0
        stopMode = 'time';
        stopAt   = burst.runSeconds;
    else
        stopMode = 'bursts';
        stopAt   = burst.numBursts * burst.txPeriodFrames;     % frames
    end

    % --- random patterns: seed if requested ---
    isRandom = any(strcmp(burst.jammerPattern, {'random', 'random_bursts'}));
    if isRandom && burst.jamRandomSeed ~= 0
        rng(burst.jamRandomSeed);
    end

    % --- live displays ---
    ts = []; cd_jam = [];
    if params.tx.liveDisplay
        ts = timescope('SampleRate', params.tx.fs, ...
            'TimeSpanSource','property','TimeSpan', frameLen/params.tx.fs, ...
            'Title','TX Burst: ch1 real / ch2 jammer', ...
            'ChannelNames',{'ch1 real (Re)','ch2 jammer (Re)'}, ...
            'AxesScaling','Auto');
        cd_jam = comm.ConstellationDiagram( ...
            'Title','TX Jammer Constellation', ...
            'ShowReferenceConstellation',false, ...
            'XLimits',[-2 2],'YLimits',[-2 2]);
    end
    c = onCleanup(@() tx_cleanup(ts, cd_jam));

    % --- header ---
    fprintf('\nBurst TX: mode=%d type=%d  pattern=%s\n', ...
            phase.mode, phase.type, burst.jammerPattern);
    fprintf('  framesPerBurst=%d  txPeriodFrames=%d  framesPerSec=%.1f\n', ...
            burst.framesPerBurst, burst.txPeriodFrames, framesPerSec);
    if strcmp(stopMode, 'bursts')
        fprintf('  stop after %d bursts (~%.1f s wall-time)\n', ...
                burst.numBursts, stopAt / framesPerSec);
    else
        fprintf('  stop after %.1f s wall-time\n', stopAt);
    end
    fprintf('  jammer waveform: %s\n\n', phase.label);

    % --- pre-burst silence (lets RX warm up + finish calib uncontaminated) ---
    if burst.delayBeforeStartSec > 0
        fprintf('Pre-burst silence: %.1f s (RX warm-up window)...\n', ...
                burst.delayBeforeStartSec);
        t_delay = tic;
        silent = [zero_ch, zero_ch];
        while toc(t_delay) < burst.delayBeforeStartSec
            try, tx(silent); catch, end
        end
        fprintf('Pre-burst silence done.\n');
    end

    % --- main loop ---
    t0 = tic; iter = 0; consecErr = 0; underrunCnt = 0;
    lastBurstIdx = -1;
    currentBurstJamDecision = true;   % only used by 'random_bursts'
    txMat = [zero_ch, zero_ch];

    while keep_running(t0, iter, stopMode, stopAt)
        if uiCtx.shouldStop(), break; end
        iter = iter + 1;
        frameIdx = iter - 1;                                 % 0-based
        burstPos = mod(frameIdx, burst.txPeriodFrames);
        burstIdx = floor(frameIdx / burst.txPeriodFrames) + 1; % 1-based
        tx_on    = burstPos < burst.framesPerBurst;

        % roll per-burst random decision at burst edge (before deciding jam_on)
        if burstIdx ~= lastBurstIdx
            if strcmp(burst.jammerPattern, 'random_bursts') && jam_available
                currentBurstJamDecision = rand() < burst.jamRandomProb;
            end
        end

        jam_on = decide_jammer(burst, frameIdx, burstIdx, ...
                               burstPos, tx_on, jam_available, ...
                               currentBurstJamDecision);

        % build the two-channel slot
        if tx_on,  txMat(:,1) = real_frame; else, txMat(:,1) = zero_ch; end
        if jam_on, txMat(:,2) = jammer;     else, txMat(:,2) = zero_ch; end

        % log burst-edge transitions
        if burstIdx ~= lastBurstIdx
            lastBurstIdx = burstIdx;
            elapsed = toc(t0);
            if jam_available
                jamRmsRatio = rms(jammer) / max(tx_rms, 1e-12);
            else
                jamRmsRatio = 0;
            end
            tagTxt = '';
            if strcmp(burst.jammerPattern, 'random_bursts')
                if currentBurstJamDecision, tagTxt = ' [jam=YES]'; else, tagTxt = ' [jam=no]'; end
            elseif strcmp(burst.jammerPattern, 'single_shot')
                if burstIdx == burst.singleShotBurst, tagTxt = ' [SINGLE SHOT]'; end
            end
            fprintf('[%6.1fs] >>> burst %d starts | jam_rms/tx_rms=%.2f%s\n', ...
                    elapsed, burstIdx, jamRmsRatio, tagTxt);
            if params.tx.liveDisplay
                ts([real(txMat(:,1)), real(txMat(:,2))]);
                if jam_available
                    feed_jam_const(cd_jam, jammer, info);
                end
            end
        end

        try
            underrun = tx(txMat);  consecErr = 0;
        catch ME
            consecErr = consecErr + 1;
            fprintf('[%6.1fs] tx exception (#%d): %s\n', ...
                    toc(t0), consecErr, ME.message);
            if consecErr == 5,  try, release(tx); catch, end, end
            if consecErr >= 10
                error('10 consecutive tx failures, check USB/connection. Last: %s', ME.message);
            end
            pause(0.1);
            continue;
        end
        if underrun, underrunCnt = underrunCnt + 1; end

        if params.tx.liveDisplay && mod(iter, params.tx.displayEvery) == 0
            ts([real(txMat(:,1)), real(txMat(:,2))]);
            if jam_available
                feed_jam_const(cd_jam, txMat(:,2), info);
            end
        end

        uiCtx.onProgress(iter, burstIdx, underrunCnt);
    end

    fprintf('\nBurst TX complete. Frames sent=%d, underruns=%d.\n', iter, underrunCnt);
end

function go = keep_running(t0, iter, stopMode, stopAt)
    switch stopMode
        case 'time',   go = toc(t0) < stopAt;
        case 'bursts', go = iter < stopAt;
        otherwise,     go = false;
    end
end

function jam_on = decide_jammer(burst, frameIdx, burstIdx, burstPos, tx_on, jam_available, currentBurstJamDecision)
    if ~jam_available, jam_on = false; return; end
    switch burst.jammerPattern
        case 'continuous'
            jam_on = true;
        case 'periodic'
            if burst.alignJamToTx
                jam_on = tx_on;
            else
                jamPos = mod(frameIdx, burst.jamPeriodFrames);
                jam_on = jamPos < burst.jamOnFrames;
            end
        case 'random'
            jam_on = rand() < burst.jamRandomProb;
        case 'random_bursts'
            % per-burst Bernoulli (decision rolled in main loop at edge);
            % jam only during the TX-on window of selected bursts
            jam_on = tx_on && currentBurstJamDecision;
        case 'single_shot'
            if burstIdx ~= burst.singleShotBurst
                jam_on = false;
            elseif strcmp(burst.singleShotJamOn, 'tx_on')
                jam_on = tx_on;
            else
                jam_on = true;            % 'full_period'
            end
        otherwise
            error('Unknown jammerPattern: %s', burst.jammerPattern);
    end
end

function validate_burst(burst)
    if burst.framesPerBurst > burst.txPeriodFrames
        error(['burst.framesPerBurst (%d) > burst.txPeriodFrames (%d). ' ...
               'On-time cannot exceed the period.'], ...
              burst.framesPerBurst, burst.txPeriodFrames);
    end
    valid = {'continuous','periodic','random','random_bursts','single_shot'};
    if ~ismember(burst.jammerPattern, valid)
        error('Unknown burst.jammerPattern "%s". Valid: %s', ...
              burst.jammerPattern, strjoin(valid, ', '));
    end
    if strcmp(burst.jammerPattern, 'single_shot') && burst.runSeconds <= 0
        if burst.singleShotBurst > burst.numBursts
            warning(['singleShotBurst (%d) > numBursts (%d): jammer will ' ...
                     'never fire. Increase numBursts or use runSeconds.'], ...
                    burst.singleShotBurst, burst.numBursts);
        end
    end
    if strcmp(burst.jammerPattern, 'periodic') && ...
       burst.jamOnFrames > burst.jamPeriodFrames
        error('jamOnFrames (%d) > jamPeriodFrames (%d)', ...
              burst.jamOnFrames, burst.jamPeriodFrames);
    end
end

function tx_cleanup(ts, cd_jam)
    if ~isempty(ts),     try, release(ts);     catch, end, end
    if ~isempty(cd_jam), try, release(cd_jam); catch, end, end
end
