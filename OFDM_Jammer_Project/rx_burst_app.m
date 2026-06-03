function rx_burst_app()
% rx_burst_app  uifigure dashboard for run_rx_burst.
%   Press Start -> RX runs forever until Stop (or window close).
%   No mode selection, no auto-stop, no TX-burst inference.  Internally
%   pinned to mode 0 baseline rxcfg; runSeconds is overridden to inf.
%
%   Features:
%     - Live BER vs bucket (semilog) + SNR vs bucket charts
%     - Bucket size spinner (rxFramesPerReport)
%     - Save / Load preset (.mat)
%     - Snapshot (PNG dump of every open figure incl. the legacy ones)
%     - Dry run (no USRP) - synthesizes bucket data so you can verify
%       the plot wiring without hardware

    addpath(genpath(fileparts(mfilename('fullpath'))));

    PINNED_MODE = 0;   % baseline rxcfg; see core/default_rxcfg.m

    % ---- figure ------------------------------------------------------
    fig = uifigure('Name', 'Burst RX Lab', 'Position', [80 60 980 560]);
    setappdata(fig, 'running',       false);
    setappdata(fig, 'stopRequested', false);

    outer = uigridlayout(fig, [1 2]);
    outer.ColumnWidth = {320, '1x'};
    outer.Padding     = [10 10 10 10];

    leftCol = uigridlayout(outer, [10 2]);
    leftCol.RowHeight   = repmat({'fit'}, 1, 10);
    leftCol.ColumnWidth = {140, '1x'};
    leftCol.RowSpacing  = 6;
    leftCol.Padding     = [0 0 0 0];

    rightCol = uigridlayout(outer, [2 1]);
    rightCol.RowHeight = {'1x', '1x'};
    rightCol.Padding   = [0 0 0 0];

    defBurst = default_burst_opts();

    % ---- bucket size -------------------------------------------------
    spRxReport = add_spinner(leftCol, 'rxFramesPerReport:', defBurst.rxFramesPerReport, [1 100000]);

    % ---- logging -----------------------------------------------------
    uilabel(leftCol, 'Text', '');
    cbLogToMat = uicheckbox(leftCol, 'Text', 'Save log to .mat at end', ...
                                     'Value', defBurst.logToMat);

    uilabel(leftCol, 'Text', 'log path (blank = auto):');
    efLogPath = uieditfield(leftCol, 'text', 'Value', defBurst.logMatPath);

    % ---- dry run -----------------------------------------------------
    uilabel(leftCol, 'Text', '');
    cbDryRun = uicheckbox(leftCol, 'Text', 'Dry run (synthesize buckets)', 'Value', false);

    % ---- diagnostic windows ------------------------------------------
    uilabel(leftCol, 'Text', '');
    cbShowDiag = uicheckbox(leftCol, ...
        'Text', 'Show spectrum / timescope / constellation / dashboard', ...
        'Value', true);

    % ---- preset + snapshot row --------------------------------------
    uilabel(leftCol, 'Text', '');
    miscRow = uigridlayout(leftCol, [1 3]);
    miscRow.ColumnSpacing = 8;
    miscRow.Padding = [0 0 0 0];
    btnSave = uibutton(miscRow, 'Text', 'Save preset...');
    btnLoad = uibutton(miscRow, 'Text', 'Load preset...');
    btnSnap = uibutton(miscRow, 'Text', '📸 Snapshot');

    % ---- start / stop ------------------------------------------------
    uilabel(leftCol, 'Text', '');
    btnRow = uigridlayout(leftCol, [1 2]);
    btnRow.ColumnSpacing = 10;
    btnRow.Padding = [0 0 0 0];
    btnStart = uibutton(btnRow, 'Text', '▶ Start RX', ...
                        'BackgroundColor', [0.55 0.78 0.55], ...
                        'FontWeight', 'bold');
    btnStop  = uibutton(btnRow, 'Text', '⏹ Stop', ...
                        'BackgroundColor', [0.88 0.62 0.62], ...
                        'FontWeight', 'bold', 'Enable', 'off');

    uilabel(leftCol, 'Text', 'Status:');
    lblStatus = uilabel(leftCol, 'Text', 'idle', 'FontWeight', 'bold');

    uilabel(leftCol, 'Text', 'Cumulative:');
    lblCum = uilabel(leftCol, 'Text', '—');

    % ---- right column: live charts ----------------------------------
    axBER = uiaxes(rightCol);
    axBER.YScale = 'log';
    axBER.YLim = [1e-5 1];
    axBER.XLabel.String = 'bucket index';
    axBER.YLabel.String = 'BER';
    axBER.Title.String  = 'BER per bucket';
    grid(axBER, 'on');
    linBER = animatedline(axBER, 'Marker','o', 'LineStyle','-', ...
                                  'Color', [0.85 0.15 0.15]);

    axSNR = uiaxes(rightCol);
    axSNR.XLabel.String = 'bucket index';
    axSNR.YLabel.String = 'SNR (dB)';
    axSNR.Title.String  = 'SNR per bucket';
    grid(axSNR, 'on');
    linSNR = animatedline(axSNR, 'Marker','s', 'LineStyle','-', ...
                                  'Color', [0.15 0.45 0.85]);

    % ---- callbacks --------------------------------------------------
    btnStart.ButtonPushedFcn = @(~,~) onStart();
    btnStop.ButtonPushedFcn  = @(~,~) onStop();
    btnSave.ButtonPushedFcn  = @(~,~) onSavePreset();
    btnLoad.ButtonPushedFcn  = @(~,~) onLoadPreset();
    btnSnap.ButtonPushedFcn  = @(~,~) onSnapshot();
    fig.CloseRequestFcn      = @(~,~) onClose();

    function onStart()
        if getappdata(fig, 'running'), return; end
        setappdata(fig, 'running',       true);
        setappdata(fig, 'stopRequested', false);
        btnStart.Enable = 'off';
        btnStop.Enable  = 'on';
        lblStatus.Text  = 'starting...';
        clearpoints(linBER); clearpoints(linSNR);
        lblCum.Text = '—';
        drawnow;

        try
            run_session();
        catch ME
            lblStatus.Text = sprintf('ERROR: %s', ME.message);
            fprintf(2, 'rx_burst_app run error:\n%s\n', getReport(ME));
        end

        wasStopped = getappdata(fig, 'stopRequested');
        setappdata(fig, 'running', false);
        btnStart.Enable = 'on';
        btnStop.Enable  = 'off';
        if wasStopped, lblStatus.Text = 'stopped';
        else,          lblStatus.Text = 'finished'; end
    end

    function onStop()
        setappdata(fig, 'stopRequested', true);
        lblStatus.Text = 'stopping...';
    end

    function onClose()
        setappdata(fig, 'stopRequested', true);
        delete(fig);
    end

    function run_session()
        burst = defBurst;
        burst.rxFramesPerReport = spRxReport.Value;
        burst.rxAutoStopIdleSec = 0;       % never auto-stop
        burst.inferTxBurstOnRx  = false;   % no TX-burst inference
        burst.logToMat          = cbLogToMat.Value;
        burst.logMatPath        = efLogPath.Value;

        params = load_parameters();
        params.sched.runSeconds = inf;     % run until user presses Stop

        sched = mode_registry('schedule', params, PINNED_MODE);
        if isempty(sched)
            error('No schedule entry for mode %d.', PINNED_MODE);
        end
        phase = sched(1);

        uiCtx = struct( ...
            'shouldStop', @() getappdata(fig, 'stopRequested'), ...
            'onBucket',   @(bIdx, snr, ber, txMin, txMax, cSNR, cBER, totDet, crcRate) ...
                          ui_on_bucket(bIdx, snr, ber, cSNR, cBER, totDet, crcRate), ...
            'headless',   ~cbShowDiag.Value);

        lblStatus.Text = 'running';
        drawnow;

        if cbDryRun.Value
            run_dry_rx(params, burst, phase, uiCtx);
        else
            rx = init_usrp_rx(params);
            cleanupObj = onCleanup(@() safe_release(rx)); %#ok<NASGU>
            run_rx_burst(params, burst, phase, rx, uiCtx);
        end
    end

    function ui_on_bucket(bucketIdx, meanSNR, meanBER, cumSNR, cumBER, totalFramesDet, crcRate)
        addpoints(linBER, bucketIdx, max(meanBER, 1e-6));     % log floor
        addpoints(linSNR, bucketIdx, meanSNR);
        lblCum.Text = sprintf( ...
            'frames=%d  cumSNR=%.1fdB  cumBER=%.2e   last bucket SNR=%.1fdB BER=%.2e CRC=%.0f%%', ...
            totalFramesDet, cumSNR, cumBER, meanSNR, meanBER, 100*crcRate);
        drawnow limitrate;
    end

    function onSavePreset()
        [file, path] = uiputfile({'*.mat', 'Burst RX preset (*.mat)'}, ...
                                 'Save preset', 'rx_burst_preset.mat');
        if isequal(file, 0), return; end
        preset = collect_preset();                                       %#ok<NASGU>
        save(fullfile(path, file), '-struct', 'preset');
        lblStatus.Text = sprintf('saved preset: %s', file);
    end

    function onLoadPreset()
        [file, path] = uigetfile({'*.mat', 'Burst RX preset (*.mat)'}, ...
                                 'Load preset');
        if isequal(file, 0), return; end
        preset = load(fullfile(path, file));
        apply_preset(preset);
        lblStatus.Text = sprintf('loaded preset: %s', file);
    end

    function onSnapshot()
        try
            folder = snapshot_figs('rx');
            lblStatus.Text = sprintf('snapshot: %s', folder);
        catch ME
            lblStatus.Text = sprintf('snapshot failed: %s', ME.message);
        end
    end

    function preset = collect_preset()
        preset.rxFramesPerReport  = spRxReport.Value;
        preset.logToMat           = cbLogToMat.Value;
        preset.logMatPath         = efLogPath.Value;
        preset.dryRun             = cbDryRun.Value;
        preset.showDiag           = cbShowDiag.Value;
    end

    function apply_preset(p)
        if isfield(p,'rxFramesPerReport'),spRxReport.Value = p.rxFramesPerReport; end
        if isfield(p,'logToMat'),         cbLogToMat.Value = logical(p.logToMat); end
        if isfield(p,'logMatPath'),       efLogPath.Value  = p.logMatPath;        end
        if isfield(p,'dryRun'),           cbDryRun.Value   = logical(p.dryRun);   end
        if isfield(p,'showDiag'),         cbShowDiag.Value = logical(p.showDiag); end
    end
end

% =====================================================================
%  Helpers
% =====================================================================

function sp = add_spinner(gl, label, val, lims)
    uilabel(gl, 'Text', label);
    sp = uispinner(gl, 'Value', val, 'Limits', lims, 'Step', 1, ...
                       'RoundFractionalValues', true);
end

function safe_release(obj)
    try, release(obj); catch, end
end

function run_dry_rx(params, burst, phase, uiCtx)
% run_dry_rx  Stand-in for run_rx_burst that needs no USRP.  Generates
% synthetic per-bucket data so the live plots and cumulative label
% update.  Runs until the user presses Stop.

    [real_frame, ~, refs] = build_frame(params.spec);
    framesPerSec  = params.tx.fs / length(real_frame);
    bitsPerFrame  = refs.bits_per_frame;
    bucketSec     = burst.rxFramesPerReport / framesPerSec;
    bucketSec     = max(bucketSec / 5, 0.05);    % 5x speed-up for dry

    fprintf('[dry-rx] mode=%d  rxFramesPerReport=%d  bucketSec(sim)=%.2f\n', ...
            phase.mode, burst.rxFramesPerReport, bucketSec);

    bucketIdx      = 0;
    cumBitsGood    = 0;
    cumBitsAll     = 0;
    cumSNRSum      = 0;
    cumSNRn        = 0;
    totalFramesDet = 0;

    while true
        if uiCtx.shouldStop(), break; end
        pause(bucketSec);
        bucketIdx = bucketIdx + 1;

        % synthetic: mostly clean, periodic "jam" buckets to show plot shape
        if mod(bucketIdx, 7) == 0 || mod(bucketIdx, 11) == 0
            meanSNR = 4 + randn();
            meanBER = 0.2 + 0.1*rand();
        else
            meanSNR = 18 + randn();
            meanBER = max(1e-5, 5e-5 + 5e-5 * rand());
        end

        totalFramesDet = totalFramesDet + burst.rxFramesPerReport;
        cumBitsAll  = cumBitsAll  + bitsPerFrame * burst.rxFramesPerReport;
        cumBitsGood = cumBitsGood + bitsPerFrame * burst.rxFramesPerReport * (1 - meanBER);
        cumSNRSum   = cumSNRSum + meanSNR * burst.rxFramesPerReport;
        cumSNRn     = cumSNRn + burst.rxFramesPerReport;
        cumSNR = cumSNRSum / max(cumSNRn,1);
        cumBER = 1 - cumBitsGood / max(cumBitsAll,1);

        uiCtx.onBucket(bucketIdx, meanSNR, meanBER, ...
                       NaN, NaN, cumSNR, cumBER, totalFramesDet);
    end
    fprintf('[dry-rx] stopped. buckets=%d\n', bucketIdx);
end
