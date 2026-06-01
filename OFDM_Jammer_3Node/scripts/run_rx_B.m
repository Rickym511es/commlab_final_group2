function run_rx_B(params, rx)
% run_rx_B  Node B victim RX loop. Adapted from the 2-node run_rx_loop:
%   * no per-phase schedule (B is the victim; it can't label the attack) -
%     a single fixed rxOpt = default_rxcfg(params) runs the whole session;
%   * link-quality banner from params.detect thresholds + baseline SNR.
% Everything else (process_capture, dashboard, raw/flower constellation)
% is reused from OFDM_Jammer_Project.

    rf  = params.rf;  spec = rf.spec;
    fs  = rf.fs;
    [~, ~, refs] = build_frame(spec);

    rxOpt = default_rxcfg(params);     % fixed: full chain, autocorr detector
    rxOpt.modeLabel = 'victim';

    sa = spectrumAnalyzer('SampleRate', fs, ...
        'ViewType','spectrum-and-spectrogram', ...
        'Title','Node B RX Spectrum (jammer energy shows here)','ShowLegend',false);
    ts_rx = timescope('SampleRate', fs, ...
        'TimeSpanSource','property','TimeSpan', params.B.samplesPerFrame/fs, ...
        'Title','Node B RX Time Domain (I/Q)', ...
        'ChannelNames',{'In-phase (I)','Quadrature (Q)'}, 'AxesScaling','Auto');
    ref_const = qammod(0:spec.qam_num-1, spec.qam_num, 'UnitAveragePower', true);
    cd_rx = comm.ConstellationDiagram('Title','Node B Equalized Constellation', ...
        'ShowReferenceConstellation',true,'ReferenceConstellation',ref_const, ...
        'XLimits',[-2 2],'YLimits',[-2 2]);
    dash = make_dashboard();
    c = onCleanup(@() rx_cleanup(sa, cd_rx, ts_rx));

    runSeconds   = params.monitor.runSeconds;
    calibSeconds = params.monitor.calibSeconds;
    displayEvery = params.monitor.displayEvery;

    fprintf('Warm-up...\n');
    for k = 1:5, try, rx(); catch, end, end
    fprintf('Warm-up done. Bring up node A now (and C when ready).\n');
    fprintf('\nMonitoring for %d s, calibration window %d s.\n\n', runSeconds, calibSeconds);

    t0 = tic; iter = 0; consecErr = 0;
    framesDetected = 0; goodBits = 0;
    calibSNR = []; baselineSNR = NaN;
    WIN = 40;
    recentDet = false(1,WIN); recentSNR = nan(1,WIN); recentBER = nan(1,WIN);
    ridx = 0; lastLog = -inf; curTight = NaN;

    while toc(t0) < runSeconds
        iter = iter + 1;
        elapsed = toc(t0);
        try
            [data,len,~] = rx();  consecErr = 0;
        catch ME
            consecErr = consecErr + 1;
            if consecErr == 5, try, release(rx); catch, end, end
            if consecErr >= 10
                error('Receive failures on node B, check connection. Last: %s', ME.message);
            end
            pause(0.1); continue;
        end
        if len == 0, continue; end

        res = process_capture(data, refs.sts, refs.lts, refs.frame_len, spec, ...
                              fs, refs.tx_bits, refs.tx_data_syms, ...
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

        if elapsed < calibSeconds
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

        if mod(iter, displayEvery) == 0
            sa(data);
            ts_rx([real(data(:)), imag(data(:))]);
            if res.detected, cd_rx(res.eq_data_syms(:)); end

            detRate  = mean(recentDet);
            recSNR   = mean(recentSNR, 'omitnan');
            recBER   = mean(recentBER, 'omitnan');
            tputKbps = goodBits / max(elapsed,1e-3) / 1e3;

            if elapsed < calibSeconds || isnan(baselineSNR)
                statusTxt = 'CALIBRATING...'; statusCol = [0.85 0.65 0.1];
            else
                jammed = false;
                if ~isnan(recSNR) && recSNR < baselineSNR - params.detect.snrDropDb, jammed = true; end
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
                try, cd_rx.XLimits = [-lim lim]; cd_rx.YLimits = [-lim lim]; catch, end
                curTight = wantTight;
            end

            if elapsed - lastLog >= 5
                lastLog = elapsed;
                if isfield(res,'cfo_hz') && ~isnan(res.cfo_hz), cfoTxt = sprintf('%+6.0f', res.cfo_hz); else, cfoTxt = '   off'; end
                fprintf('[%6.1fs] %-16s | det=%3.0f%% SNR=%5.1fdB BER=%.2e cfo=%sHz\n', ...
                    elapsed, statusTxt, 100*detRate, recSNR, recBER, cfoTxt);
            end
        end
    end
    fprintf('\nMonitoring complete. Frames detected = %d.\n', framesDetected);
end

function rx_cleanup(sa, cd_rx, ts_rx)
    try, release(sa);    catch, end
    try, release(cd_rx); catch, end
    try, release(ts_rx); catch, end
end
