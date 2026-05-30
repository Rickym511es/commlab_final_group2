function run_rx_burst(params, burst, phase, rx, uiCtx)
% run_rx_burst  RX while-loop with per-burst stat accumulation.
% Mirrors run_rx_loop's capture+process flow, but replaces the rolling
% WIN=40 window with discrete buckets of rxFramesPerReport detected
% frames, and prints a per-bucket summary so you can score each TX burst
% against the chosen jammer pattern.
%
% Optional 5th arg uiCtx exposes hooks for UI integration:
%   uiCtx.shouldStop : function handle, no args, returns logical.
%   uiCtx.onBucket   : function handle taking
%                      (bucketIdx, meanSNR_dB, meanBER, txMin, txMax,
%                       cumSNR_dB, cumBER, totalFramesDet).
%                      Called when a bucket flushes so UI can plot/log.
% Pass [] or omit for non-UI use.

    if nargin < 5 || isempty(uiCtx)
        uiCtx = struct('shouldStop', @() false, ...
                       'onBucket',   @(varargin) []);
    end

    spec = params.spec;
    [~, ~, refs] = build_frame(spec);

    sa = spectrumAnalyzer('SampleRate', params.rx.fs, ...
        'ViewType','spectrum-and-spectrogram', ...
        'Title','RX Spectrum','ShowLegend',false);
    ts_rx = timescope('SampleRate', params.rx.fs, ...
        'TimeSpanSource','property','TimeSpan', params.rx.samplesPerFrame/params.rx.fs, ...
        'Title','RX Time Domain', ...
        'ChannelNames',{'In-phase (I)','Quadrature (Q)'}, ...
        'AxesScaling','Auto');
    ref_const = qammod(0:spec.qam_num-1, spec.qam_num, 'UnitAveragePower', true);
    cd_rx = comm.ConstellationDiagram( ...
        'Title','RX Equalized Constellation', ...
        'ShowReferenceConstellation',true, ...
        'ReferenceConstellation',ref_const, ...
        'XLimits',[-2 2],'YLimits',[-2 2]);

    dash = make_dashboard();
    c = onCleanup(@() rx_cleanup(sa, cd_rx, ts_rx));

    fprintf('Warm-up...\n');
    for k = 1:5, try, rx(); catch, end, end
    fprintf('Warm-up done.  Run tx_burst_console(%d,...) in the other window.\n', phase.mode);
    fprintf('\nMonitoring %d s, calib %d s.  Burst size = %d detected frames.\n\n', ...
            params.sched.runSeconds, params.sched.calibSeconds, burst.rxFramesPerReport);

    rxOpt = phase.descriptor.rxcfg(default_rxcfg(params), params);

    % --- per-burst accumulators ---
    burstIdx       = 0;
    burstFrames    = 0;
    burstSNRSum    = 0;
    burstBERSum    = 0;
    burstStartSec  = 0;

    % --- cumulative ---
    totalFramesDet = 0;
    totalBitsGood  = 0;       % sum of (1 - BER) * bits_per_frame
    totalBitsAll   = 0;       % bits_per_frame * detected
    cumSNRSum      = 0;
    cumSNRn        = 0;

    % --- calibration / live dashboard helpers ---
    calibSNR    = [];
    baselineSNR = NaN;
    WIN = 40;
    recentDet = false(1,WIN); recentSNR = nan(1,WIN); recentBER = nan(1,WIN);
    ridx = 0; curTight = NaN;

    % --- gap-based TX-burst inference ---
    framesPerSec    = params.tx.fs / refs.frame_len;
    expectedOffSec  = max(0, (burst.txPeriodFrames - burst.framesPerBurst) / framesPerSec);
    minUsefulOffSec = 10 * refs.frame_len / params.tx.fs;     % 10 frames worth
    if expectedOffSec < minUsefulOffSec
        % degenerate: TX is on ~100%, no off-window to bracket bursts.
        % set threshold to infinity so first detection bumps once and stays.
        gapThresholdSec = inf;
        if burst.inferTxBurstOnRx
            fprintf(['TX-burst inference: off-window=%.0fms < %.0fms heuristic floor; ' ...
                     'will report all frames as TX burst 1.\n'], ...
                    expectedOffSec*1000, minUsefulOffSec*1000);
        end
    else
        gapThresholdSec = 0.5 * expectedOffSec;
        if burst.inferTxBurstOnRx
            fprintf('TX-burst inference armed: expectedOff=%.0f ms, gapThresh=%.0f ms.\n', ...
                    expectedOffSec*1000, gapThresholdSec*1000);
        end
    end
    inferredTxBurst   = 0;
    lastDetSec        = NaN;
    bucketTxBurstMin  = NaN;
    bucketTxBurstMax  = NaN;
    if burst.rxAutoStopIdleSec > 0
        fprintf('Auto-stop armed: stop after %.1f s idle (post first detection).\n', ...
                burst.rxAutoStopIdleSec);
    end

    % --- per-bucket log (for .mat save / offline plotting) ---
    logIdx        = [];
    logFrames     = [];
    logMeanSNR    = [];
    logMeanBER    = [];
    logDur        = [];
    logStartSec   = [];
    logTxBurstMin = [];
    logTxBurstMax = [];

    t0 = tic; iter = 0; consecErr = 0;

    while toc(t0) < params.sched.runSeconds
        iter    = iter + 1;
        elapsed = toc(t0);

        % UI stop signal
        if uiCtx.shouldStop(), break; end

        % auto-stop: armed only after the first detection so RX still
        % survives a slow TX start
        if burst.rxAutoStopIdleSec > 0 && totalFramesDet > 0 && ...
           ~isnan(lastDetSec) && (elapsed - lastDetSec) > burst.rxAutoStopIdleSec
            fprintf('[%6.1fs] auto-stop: no detection for >%.1f s (TX likely done).\n', ...
                    elapsed, burst.rxAutoStopIdleSec);
            break;
        end

        try
            [data,len,~] = rx();  consecErr = 0;
        catch ME
            consecErr = consecErr + 1;
            if consecErr == 5, try, release(rx); catch, end, end
            if consecErr >= 10
                error('Receive failures, check connection. Last: %s', ME.message);
            end
            pause(0.1);
            continue;
        end
        if len == 0, continue; end

        res = process_capture(data, refs.sts, refs.lts, refs.frame_len, spec, ...
                              params.rx.fs, refs.tx_bits, refs.tx_data_syms, ...
                              refs.pilot_syms, refs.lts_f_known, ...
                              params.detect.detectRatio, rxOpt);

        % rolling buffer for the live dashboard panel
        ridx = mod(ridx, WIN) + 1;
        recentDet(ridx) = res.detected;
        if res.detected
            recentSNR(ridx) = res.snr_dB;  recentBER(ridx) = res.ber;
        else
            recentSNR(ridx) = NaN;  recentBER(ridx) = NaN;
        end

        % --- per-burst accumulation (detected frames only) ---
        if res.detected
            % gap-based TX-burst inference: if we waited "too long"
            % since the last detection, TX must have crossed an off-window
            if burst.inferTxBurstOnRx
                if isnan(lastDetSec) || (elapsed - lastDetSec) > gapThresholdSec
                    inferredTxBurst = inferredTxBurst + 1;
                end
            end
            lastDetSec = elapsed;

            if burstFrames == 0
                burstIdx      = burstIdx + 1;
                burstStartSec = elapsed;
                bucketTxBurstMin = inferredTxBurst;
                bucketTxBurstMax = inferredTxBurst;
            else
                bucketTxBurstMax = inferredTxBurst;   % monotonic
            end
            burstFrames = burstFrames + 1;
            burstSNRSum = burstSNRSum + res.snr_dB;
            burstBERSum = burstBERSum + res.ber;

            totalFramesDet = totalFramesDet + 1;
            cumSNRSum      = cumSNRSum + res.snr_dB;
            cumSNRn        = cumSNRn + 1;
            totalBitsAll   = totalBitsAll  + refs.bits_per_frame;
            totalBitsGood  = totalBitsGood + refs.bits_per_frame * max(0, 1 - res.ber);

            if burstFrames >= burst.rxFramesPerReport
                meanSNR = burstSNRSum / burstFrames;
                meanBER = burstBERSum / burstFrames;
                dur     = elapsed - burstStartSec;
                cumBER  = 1 - totalBitsGood / max(totalBitsAll, 1);
                cumSNR  = cumSNRSum / max(cumSNRn, 1);
                if burst.rxVerbose
                    if burst.inferTxBurstOnRx
                        if bucketTxBurstMin == bucketTxBurstMax
                            txTag = sprintf('tx=%d', bucketTxBurstMin);
                        else
                            txTag = sprintf('tx=%d..%d', bucketTxBurstMin, bucketTxBurstMax);
                        end
                    else
                        txTag = '';
                    end
                    fprintf(['[bucket %3d] frames=%d dur=%5.2fs %s ' ...
                             'SNR=%5.1fdB BER=%.2e  ||  ' ...
                             'cum frames=%d cumSNR=%5.1fdB cumBER=%.2e\n'], ...
                            burstIdx, burstFrames, dur, txTag, ...
                            meanSNR, meanBER, ...
                            totalFramesDet, cumSNR, cumBER);
                end

                % append to log vectors
                logIdx(end+1)        = burstIdx;        %#ok<AGROW>
                logFrames(end+1)     = burstFrames;     %#ok<AGROW>
                logMeanSNR(end+1)    = meanSNR;         %#ok<AGROW>
                logMeanBER(end+1)    = meanBER;         %#ok<AGROW>
                logDur(end+1)        = dur;             %#ok<AGROW>
                logStartSec(end+1)   = burstStartSec;   %#ok<AGROW>
                logTxBurstMin(end+1) = bucketTxBurstMin;%#ok<AGROW>
                logTxBurstMax(end+1) = bucketTxBurstMax;%#ok<AGROW>

                % UI hook for live plots
                uiCtx.onBucket(burstIdx, meanSNR, meanBER, ...
                               bucketTxBurstMin, bucketTxBurstMax, ...
                               cumSNR, cumBER, totalFramesDet);

                burstFrames = 0; burstSNRSum = 0; burstBERSum = 0;
                bucketTxBurstMin = NaN; bucketTxBurstMax = NaN;
            end
        end

        % baseline SNR calibration (first calibSeconds)
        if elapsed < params.sched.calibSeconds
            if res.detected, calibSNR(end+1) = res.snr_dB; end %#ok<AGROW>
        elseif isnan(baselineSNR)
            if ~isempty(calibSNR)
                baselineSNR = median(calibSNR);
                fprintf('Baseline SNR calibrated: %.1f dB\n', baselineSNR);
            else
                baselineSNR = 0;
                fprintf('Warning: no frames during calib, baselineSNR=0.\n');
            end
        end

        % live dashboard refresh
        if mod(iter, params.rx.displayEvery) == 0
            sa(data);
            ts_rx([real(data(:)), imag(data(:))]);
            if res.detected
                cd_rx(res.eq_data_syms(:));
            end

            detRate  = mean(recentDet);
            recSNR   = mean(recentSNR, 'omitnan');
            recBER   = mean(recentBER, 'omitnan');
            tputKbps = totalBitsGood / max(elapsed,1e-3) / 1e3;

            if elapsed < params.sched.calibSeconds || isnan(baselineSNR)
                statusTxt = 'CALIBRATING...'; statusCol = [0.85 0.65 0.1];
            else
                jammed = false;
                if ~isnan(recSNR) && recSNR < baselineSNR - params.detect.snrDropDb, jammed = true; end
                if detRate < params.detect.detRateJam,                               jammed = true; end
                if ~isnan(recBER) && recBER > params.detect.berJam,                  jammed = true; end
                if jammed
                    statusTxt = 'JAMMING DETECTED'; statusCol = [0.85 0.15 0.15];
                else
                    statusTxt = 'LINK OK';          statusCol = [0.15 0.65 0.2];
                end
            end

            update_dashboard(dash, statusTxt, statusCol, totalFramesDet, ...
                detRate, recBER, recSNR, baselineSNR, tputKbps);

            wantTight = strcmp(statusTxt, 'LINK OK');
            if ~isequal(wantTight, curTight)
                if wantTight, lim = 1.4; else, lim = 2.5; end
                try, cd_rx.XLimits = [-lim lim]; cd_rx.YLimits = [-lim lim]; catch, end
                curTight = wantTight;
            end
        end
    end

    % --- final summary ---
    cumBER = 1 - totalBitsGood / max(totalBitsAll, 1);
    cumSNR = cumSNRSum / max(cumSNRn, 1);
    fprintf('\n=== Burst RX summary ===\n');
    fprintf('  buckets completed = %d (current bucket had %d frames pending)\n', ...
            burstIdx - (burstFrames > 0), burstFrames);
    fprintf('  total detected    = %d frames\n', totalFramesDet);
    if burst.inferTxBurstOnRx
        fprintf('  inferred TX bursts seen = %d\n', inferredTxBurst);
    end
    fprintf('  cumulative SNR    = %.2f dB\n', cumSNR);
    fprintf('  cumulative BER    = %.3e\n', cumBER);
    fprintf('  good bits         = %.0f / %.0f\n', totalBitsGood, totalBitsAll);

    % --- offline log save ---
    if burst.logToMat
        log = struct();
        log.bucketIdx          = logIdx;
        log.frames             = logFrames;
        log.meanSNR_dB         = logMeanSNR;
        log.meanBER            = logMeanBER;
        log.durSec             = logDur;
        log.startSec           = logStartSec;
        log.inferredTxBurstMin = logTxBurstMin;
        log.inferredTxBurstMax = logTxBurstMax;
        log.totalFramesDet     = totalFramesDet;
        log.cumBER             = cumBER;
        log.cumSNR_dB          = cumSNR;
        log.baselineSNR_dB     = baselineSNR;
        log.params             = params;
        log.burst              = burst;
        log.mode               = phase.mode;
        log.modeLabel          = phase.label;

        path = burst.logMatPath;
        if isempty(path)
            path = sprintf('rx_burst_log_mode%d_%s.mat', ...
                           phase.mode, datestr(now, 'yyyymmdd_HHMMSS'));
        end
        save(path, '-struct', 'log');
        fprintf('  log written to    : %s\n', path);
    end
end

function rx_cleanup(sa, cd_rx, ts_rx)
    try, release(sa);     catch, end
    try, release(cd_rx);  catch, end
    try, release(ts_rx);  catch, end
end
