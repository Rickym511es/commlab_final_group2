function tx_burst_app()
% tx_burst_app  uifigure for run_tx_burst with independent TX & jammer
% schedules.
%
%   TX schedule  : start offset (s), burst duration (s), interval (s), count
%   Jammer sched : start offset (s), attack duration (s), interval (s), count
%
%   Both timelines run on the same wall clock but are otherwise independent.
%   TX 實驗總長 (s) is the wall-clock stop; either side can finish its
%   scheduled bursts/attacks before total time and then go silent.
%
%   Internally maps to run_tx_burst's existing TX-duty cycle (framesPerBurst /
%   txPeriodFrames / numBursts / txStartOffsetFrames) plus the 'periodic'
%   jammer pattern with jamStartOffsetFrames + jamMaxFires.

    addpath(genpath(fileparts(mfilename('fullpath'))));

    % ---- figure ------------------------------------------------------
    fig = uifigure('Name', 'Burst TX Lab', 'Position', [120 40 560 860]);
    setappdata(fig, 'running',       false);
    setappdata(fig, 'stopRequested', false);

    gl = uigridlayout(fig, [20 2]);
    gl.RowHeight   = repmat({'fit'}, 1, 20);
    gl.ColumnWidth = {200, '1x'};
    gl.RowSpacing  = 5;
    gl.Padding     = [12 12 12 12];

    % ---- mode dropdown (populated from mode_registry) ----------------
    modes      = mode_registry();
    modeItems  = cell(1, numel(modes));
    modeIdData = zeros(1, numel(modes));
    for i = 1:numel(modes)
        modeItems{i}  = sprintf('%d  %s', modes{i}.id, modes{i}.todo);
        modeIdData(i) = modes{i}.id;
    end

    uilabel(gl, 'Text', 'Jammer mode:', 'FontWeight', 'bold');
    ddMode = uidropdown(gl, 'Items', modeItems, 'ItemsData', modeIdData, ...
                            'Value', 8);

    % ---- TX section header ------------------------------------------
    uilabel(gl, 'Text', '— TX 排程 —', 'FontWeight', 'bold');
    uilabel(gl, 'Text', '');

    spTxOffset    = add_dbl_spinner(gl, 'TX 起始位置 (s):',    0.0,  [0 3600], 0.1);
    spTxDuration  = add_dbl_spinner(gl, 'TX 每段發送 (s):',    1.0,  [0.01 3600], 0.1);
    spTxInterval  = add_dbl_spinner(gl, 'TX 間隔 (s):',        0.0,  [0 3600], 0.1);
    spTxCount     = add_int_spinner(gl, 'TX 次數:',            1,    [1 100000]);

    % ---- Jammer section header --------------------------------------
    uilabel(gl, 'Text', '— Jammer 排程 —', 'FontWeight', 'bold');
    uilabel(gl, 'Text', '');

    spJamOffset   = add_dbl_spinner(gl, 'Jammer 起始位置 (s):', 1.0,  [0 3600], 0.1);
    spJamDuration = add_dbl_spinner(gl, '每次攻擊持續 (s):',    0.5,  [0.01 3600], 0.05);
    spJamInterval = add_dbl_spinner(gl, '攻擊間隔 (s):',        2.0,  [0 3600], 0.1);
    spJamCount    = add_int_spinner(gl, '攻擊次數:',            5,    [1 1000]);

    % ---- run-wide controls ------------------------------------------
    uilabel(gl, 'Text', '— Run —', 'FontWeight', 'bold');
    uilabel(gl, 'Text', '');

    spTotal       = add_dbl_spinner(gl, 'TX 實驗總長 (s):',     20.0, [1 3600], 1.0);

    [slJamPower, lblJamPower] = add_power_slider(gl, 'Jammer power (jam_power_scale):', 1.0);
    [slNoisePower, lblNoisePower] = add_power_slider(gl, 'Noise power (noise_power):',  1.0);

    uilabel(gl, 'Text', '');
    cbDryRun = uicheckbox(gl, 'Text', 'Dry run (simulate, no USRP)', 'Value', false);

    uilabel(gl, 'Text', '');
    miscRow = uigridlayout(gl, [1 3]);
    miscRow.ColumnSpacing = 8;
    miscRow.Padding = [0 0 0 0];
    btnSave = uibutton(miscRow, 'Text', 'Save preset...');
    btnLoad = uibutton(miscRow, 'Text', 'Load preset...');
    btnSnap = uibutton(miscRow, 'Text', '📸 Snapshot');

    uilabel(gl, 'Text', '');
    btnRow = uigridlayout(gl, [1 2]);
    btnRow.ColumnSpacing = 10;
    btnRow.Padding = [0 0 0 0];
    btnStart = uibutton(btnRow, 'Text', '▶ Start TX', ...
                        'BackgroundColor', [0.55 0.78 0.55], ...
                        'FontWeight', 'bold');
    btnStop  = uibutton(btnRow, 'Text', '⏹ Stop', ...
                        'BackgroundColor', [0.88 0.62 0.62], ...
                        'FontWeight', 'bold', 'Enable', 'off');

    uilabel(gl, 'Text', 'Status:');
    lblStatus = uilabel(gl, 'Text', 'idle', 'FontWeight', 'bold');

    uilabel(gl, 'Text', 'Progress:');
    lblProgress = uilabel(gl, 'Text', '—');

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
        drawnow;

        try
            run_session(ddMode.Value);
        catch ME
            lblStatus.Text = sprintf('ERROR: %s', ME.message);
            fprintf(2, 'tx_burst_app run error:\n%s\n', getReport(ME));
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

    function run_session(modeId)
        txOffsetSec   = spTxOffset.Value;
        txDurationSec = spTxDuration.Value;
        txIntervalSec = spTxInterval.Value;
        txCount       = spTxCount.Value;

        jmOffsetSec   = spJamOffset.Value;
        jmDurationSec = spJamDuration.Value;
        jmIntervalSec = spJamInterval.Value;
        jmCount       = spJamCount.Value;

        runSec        = spTotal.Value;
        jamPower      = slJamPower.Value;
        noisePower    = slNoisePower.Value;
        dryRun        = cbDryRun.Value;

        params = load_parameters();
        params.knob.jam_power_scale = jamPower;
        params.knob.noise_power     = noisePower;

        [real_frame, ~, ~] = build_frame(params.spec);
        frameLen     = length(real_frame);
        framesPerSec = params.tx.fs / frameLen;

        burst = default_burst_opts();

        % --- TX schedule ---
        burst.txStartOffsetFrames = max(0, round(txOffsetSec   * framesPerSec));
        burst.framesPerBurst      = max(1, round(txDurationSec * framesPerSec));
        burst.txPeriodFrames      = max(burst.framesPerBurst, ...
                                        round((txDurationSec + txIntervalSec) * framesPerSec));
        burst.numBursts           = txCount;

        % --- Jammer schedule ---
        burst.jammerPattern         = 'periodic';
        burst.alignJamToTx          = false;
        burst.jamStartOffsetFrames  = max(0, round(jmOffsetSec   * framesPerSec));
        burst.jamOnFrames           = max(1, round(jmDurationSec * framesPerSec));
        burst.jamPeriodFrames       = max(burst.jamOnFrames, ...
                                          round((jmDurationSec + jmIntervalSec) * framesPerSec));
        burst.jamMaxFires           = jmCount;

        % --- wall-clock cap ---
        burst.runSeconds          = runSec;
        burst.delayBeforeStartSec = 0;

        sched = mode_registry('schedule', params, modeId);
        if isempty(sched)
            error('No schedule entry for mode %d.', modeId);
        end
        phase = sched(1);

        uiCtx = struct( ...
            'shouldStop', @() getappdata(fig, 'stopRequested'), ...
            'onProgress', @(iter, bIdx, ur) ui_progress(iter, ur, runSec, framesPerSec, txCount, jmCount));

        lblStatus.Text = sprintf('running mode %d', modeId);
        drawnow;

        if dryRun
            run_dry(params, burst, phase, uiCtx);
        else
            tx = init_usrp_tx(params);
            cleanupObj = onCleanup(@() safe_release(tx)); %#ok<NASGU>
            run_tx_burst(params, burst, phase, tx, uiCtx);
        end
    end

    function ui_progress(iter, underrunCnt, runSec, framesPerSec, txCount, jmCount)
        persistent lastTic
        if isempty(lastTic), lastTic = tic; end
        if toc(lastTic) < 0.05, return; end
        lastTic = tic;

        elapsedSec = iter / framesPerSec;
        lblProgress.Text = sprintf( ...
            't = %.1f / %.1f s    frames sent: %d    underruns: %d    (TX×%d, jam×%d)', ...
            elapsedSec, runSec, iter, underrunCnt, txCount, jmCount);
        drawnow limitrate;
    end

    function onSavePreset()
        [file, path] = uiputfile({'*.mat', 'Burst TX preset (*.mat)'}, ...
                                 'Save preset', 'tx_burst_preset.mat');
        if isequal(file, 0), return; end
        preset = collect_preset();                                       %#ok<NASGU>
        save(fullfile(path, file), '-struct', 'preset');
        lblStatus.Text = sprintf('saved preset: %s', file);
    end

    function onLoadPreset()
        [file, path] = uigetfile({'*.mat', 'Burst TX preset (*.mat)'}, ...
                                 'Load preset');
        if isequal(file, 0), return; end
        preset = load(fullfile(path, file));
        apply_preset(preset);
        lblStatus.Text = sprintf('loaded preset: %s', file);
    end

    function onSnapshot()
        try
            folder = snapshot_figs('tx');
            lblStatus.Text = sprintf('snapshot: %s', folder);
        catch ME
            lblStatus.Text = sprintf('snapshot failed: %s', ME.message);
        end
    end

    function preset = collect_preset()
        preset.modeId         = ddMode.Value;
        preset.txOffsetSec    = spTxOffset.Value;
        preset.txDurationSec  = spTxDuration.Value;
        preset.txIntervalSec  = spTxInterval.Value;
        preset.txCount        = spTxCount.Value;
        preset.jmOffsetSec    = spJamOffset.Value;
        preset.jmDurationSec  = spJamDuration.Value;
        preset.jmIntervalSec  = spJamInterval.Value;
        preset.jmCount        = spJamCount.Value;
        preset.runSec         = spTotal.Value;
        preset.jamPowerScale  = slJamPower.Value;
        preset.noisePower     = slNoisePower.Value;
        preset.dryRun         = cbDryRun.Value;
    end

    function apply_preset(p)
        if isfield(p,'modeId') && ismember(p.modeId, modeIdData)
            ddMode.Value = p.modeId;
        end
        set_if(p,'txOffsetSec',   spTxOffset);
        set_if(p,'txDurationSec', spTxDuration);
        set_if(p,'txIntervalSec', spTxInterval);
        set_if(p,'txCount',       spTxCount);
        set_if(p,'jmOffsetSec',   spJamOffset);
        set_if(p,'jmDurationSec', spJamDuration);
        set_if(p,'jmIntervalSec', spJamInterval);
        set_if(p,'jmCount',       spJamCount);
        set_if(p,'runSec',        spTotal);
        if isfield(p,'jamPowerScale')
            slJamPower.Value = clamp_slider(slJamPower, p.jamPowerScale);
            lblJamPower.Text = sprintf('%.2f', slJamPower.Value);
        end
        if isfield(p,'noisePower')
            slNoisePower.Value = clamp_slider(slNoisePower, p.noisePower);
            lblNoisePower.Text = sprintf('%.2f', slNoisePower.Value);
        end
        if isfield(p,'dryRun'), cbDryRun.Value = logical(p.dryRun); end
    end

    function set_if(p, field, sp)
        if isfield(p, field)
            sp.Value = max(sp.Limits(1), min(sp.Limits(2), p.(field)));
        end
    end
end

% =====================================================================
%  Helpers
% =====================================================================

function sp = add_int_spinner(gl, label, val, lims)
    uilabel(gl, 'Text', label);
    sp = uispinner(gl, 'Value', val, 'Limits', lims, 'Step', 1, ...
                       'RoundFractionalValues', true);
end

function sp = add_dbl_spinner(gl, label, val, lims, step)
    uilabel(gl, 'Text', label);
    sp = uispinner(gl, 'Value', val, 'Limits', lims, 'Step', step, ...
                       'ValueDisplayFormat', '%.2f');
end

function [sl, lbl] = add_power_slider(gl, label, val)
    uilabel(gl, 'Text', label);
    row = uigridlayout(gl, [1 2]);
    row.ColumnWidth   = {'1x', 50};
    row.ColumnSpacing = 8;
    row.Padding       = [0 0 0 0];
    sl  = uislider(row, 'Limits', [0 2], 'Value', val);
    lbl = uilabel(row, 'Text', sprintf('%.2f', val));
    sl.ValueChangingFcn = @(s,e) set(lbl, 'Text', sprintf('%.2f', e.Value));
    sl.ValueChangedFcn  = @(s,e) set(lbl, 'Text', sprintf('%.2f', s.Value));
end

function v = clamp_slider(sl, x)
    v = max(sl.Limits(1), min(sl.Limits(2), x));
end

function safe_release(obj)
    try, release(obj); catch, end
end

function run_dry(params, burst, phase, uiCtx)
% run_dry  Walks the TX timeline at 10x real speed so you can verify
% the UI without hardware.  Does NOT exercise jammer waveform code.

    [real_frame, ~, ~] = build_frame(params.spec);
    framePeriodSec  = length(real_frame) / params.tx.fs;
    sleepPerIter    = max(framePeriodSec / 10, 0.001);
    stopAtFrames    = ceil(burst.runSeconds * (params.tx.fs / length(real_frame)));

    fprintf(['[dry] mode=%d  runSec=%.1f  ' ...
             'TX off=%d on=%d period=%d count=%d  ' ...
             'JAM off=%d on=%d period=%d count=%d\n'], ...
            phase.mode, burst.runSeconds, ...
            burst.txStartOffsetFrames, burst.framesPerBurst, burst.txPeriodFrames, burst.numBursts, ...
            burst.jamStartOffsetFrames, burst.jamOnFrames, burst.jamPeriodFrames, burst.jamMaxFires);

    t0 = tic; iter = 0; underrunCnt = 0;
    while iter < stopAtFrames
        if uiCtx.shouldStop(), break; end
        iter = iter + 1;
        pause(sleepPerIter);
        uiCtx.onProgress(iter, 1, underrunCnt);
    end
    fprintf('[dry] complete. iters=%d (sim %.2fs)\n', iter, toc(t0));
end
