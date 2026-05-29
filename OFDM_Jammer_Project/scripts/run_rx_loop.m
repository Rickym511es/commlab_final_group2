function run_rx_loop(params, sched, rx)
% run_rx_loop  RX while-loop. Builds the reference frame, opens the live
% displays, then for each capture: runs process_capture with the current
% phase's rxcfg, updates rolling stats, and refreshes the dashboard.

    spec = params.spec;
    [~, ~, refs] = build_frame(spec);

    numPhases = numel(sched);

    sa = spectrumAnalyzer('SampleRate', params.rx.fs, ...
        'ViewType','spectrum-and-spectrogram', ...
        'Title','RX Spectrum (jammer energy shows here)','ShowLegend',false);

    ts_rx = timescope('SampleRate', params.rx.fs, ...
        'TimeSpanSource','property','TimeSpan', params.rx.samplesPerFrame/params.rx.fs, ...
        'Title','RX Time Domain (I/Q; amplitude spikes when jammed)', ...
        'ChannelNames',{'In-phase (I)','Quadrature (Q)'}, ...
        'AxesScaling','Auto');

    ref_const = qammod(0:spec.qam_num-1, spec.qam_num, 'UnitAveragePower', true);
    cd_rx = comm.ConstellationDiagram( ...
        'Title','RX Equalized Constellation (spreads when jammed)', ...
        'ShowReferenceConstellation',true, ...
        'ReferenceConstellation',ref_const, ...
        'XLimits',[-2 2],'YLimits',[-2 2]);

    cd_flower = comm.ConstellationDiagram( ...
        'Title','RX Raw (center subcarriers; TODO8 -> flower)', ...
        'ShowReferenceConstellation',false, ...
        'XLimits',[-3 3],'YLimits',[-3 3]);

    dash = make_dashboard();
    c = onCleanup(@() rx_cleanup(sa, cd_rx, ts_rx, cd_flower));

    fprintf('Warm-up...\n');
    for k = 1:5, try, rx(); catch, end, end
    fprintf('Warm-up done. Start tx_console in the other window now.\n');

    fprintf('\nMonitoring for %d s, calibration window %d s.\n\n', ...
            params.sched.runSeconds, params.sched.calibSeconds);

    t0 = tic; iter = 0; consecErr = 0;
    framesDetected = 0; goodBits = 0;
    calibSNR = []; baselineSNR = NaN;
    WIN = 40;
    recentDet = false(1,WIN); recentSNR = nan(1,WIN); recentBER = nan(1,WIN);
    ridx = 0; lastLog = -inf; curTight = NaN;

    numData   = length(spec.data_sc);
    midSC     = round(numData/2);
    flowerSC  = max(1,midSC-2) : min(numData,midSC+2);
    flowerMax = 4000;
    flowerBuf = [];  flowerWr = 0;

    while toc(t0) < params.sched.runSeconds
        iter = iter + 1;
        elapsed = toc(t0);
        pIdx = floor(elapsed / params.sched.secondsPerPhase) + 1;
        pIdx = max(1, min(pIdx, numPhases));
        rxOpt = default_rxcfg(params);
        rxOpt = sched(pIdx).descriptor.rxcfg(rxOpt, params);

        try
            [data,len,~] = rx();  consecErr = 0;
        catch ME
            consecErr = consecErr + 1;
            if consecErr == 5
                try, release(rx); catch, end
            end
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

        ridx = mod(ridx, WIN) + 1;
        recentDet(ridx) = res.detected;
        if res.detected
            recentSNR(ridx) = res.snr_dB;  recentBER(ridx) = res.ber;
            framesDetected = framesDetected + 1;
            goodBits = goodBits + refs.bits_per_frame * max(0, 1 - res.ber);
        else
            recentSNR(ridx) = NaN;  recentBER(ridx) = NaN;
        end

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

        if mod(iter, params.rx.displayEvery) == 0
            sa(data);
            ts_rx([real(data(:)), imag(data(:))]);
            if res.detected
                cd_rx(res.eq_data_syms(:));
                newpts = res.eq_raw_syms(flowerSC, :);  newpts = newpts(:);
                m = numel(newpts);
                if isempty(flowerBuf)
                    reps = ceil(flowerMax / max(m,1));
                    tmp = repmat(newpts, reps, 1);
                    flowerBuf = tmp(1:flowerMax);
                    flowerWr = 0;
                else
                    idx = mod(flowerWr + (0:m-1), flowerMax) + 1;
                    flowerBuf(idx) = newpts;
                    flowerWr = mod(flowerWr + m, flowerMax);
                end
                cd_flower(flowerBuf / (rms(flowerBuf)+eps));
            end

            detRate  = mean(recentDet);
            recSNR   = mean(recentSNR, 'omitnan');
            recBER   = mean(recentBER, 'omitnan');
            tputKbps = goodBits / max(elapsed,1e-3) / 1e3;

            if elapsed < params.sched.calibSeconds || isnan(baselineSNR)
                statusTxt = 'CALIBRATING...'; statusCol = [0.85 0.65 0.1];
            else
                jammed = false;
                if ~isnan(recSNR) && recSNR < baselineSNR - params.detect.snrDropDb
                    jammed = true;
                end
                if detRate < params.detect.detRateJam, jammed = true; end
                if ~isnan(recBER) && recBER > params.detect.berJam, jammed = true; end
                if jammed
                    statusTxt = 'JAMMING DETECTED'; statusCol = [0.85 0.15 0.15];
                else
                    statusTxt = 'LINK OK';          statusCol = [0.15 0.65 0.2];
                end
            end

            update_dashboard(dash, statusTxt, statusCol, framesDetected, ...
                detRate, recBER, recSNR, baselineSNR, tputKbps);

            wantTight = strcmp(statusTxt, 'LINK OK');
            if ~isequal(wantTight, curTight)
                if wantTight, lim = 1.4; else, lim = 2.5; end
                try
                    cd_rx.XLimits = [-lim lim];
                    cd_rx.YLimits = [-lim lim];
                catch
                end
                curTight = wantTight;
            end

            if elapsed - lastLog >= 5
                lastLog = elapsed;
                pTxt = sched(pIdx).label;
                if isfield(res,'cfo_hz') && ~isnan(res.cfo_hz), cfoTxt = sprintf('%+6.0f', res.cfo_hz); else, cfoTxt = '   off'; end
                if isfield(res,'fine_cfo_hz') && ~isnan(res.fine_cfo_hz), fineTxt = sprintf('%+6.0f', res.fine_cfo_hz); else, fineTxt = '   off'; end
                if isfield(res,'detect_score') && ~isnan(res.detect_score), detScoreTxt = sprintf('%.2f', res.detect_score); else, detScoreTxt = '  -- '; end
                fprintf(['[%6.1fs] %-16s | phase:%s | rx:%s | det=%3.0f%% ' ...
                         'score=%s SNR=%5.1fdB BER=%.2e cfo=%sHz fine=%sHz\n'], ...
                    elapsed, statusTxt, pTxt, rxOpt.modeLabel, 100*detRate, ...
                    detScoreTxt, recSNR, recBER, cfoTxt, fineTxt);
            end
        end
    end

    fprintf('\nMonitoring complete. Frames detected = %d.\n', framesDetected);
end

function rx_cleanup(sa, cd_rx, ts_rx, cd_flower)
    try, release(sa);        catch, end
    try, release(cd_rx);     catch, end
    try, release(ts_rx);     catch, end
    try, release(cd_flower); catch, end
end
