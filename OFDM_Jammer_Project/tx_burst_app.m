function tx_burst_app()
% tx_burst_app  uifigure control panel for tx_burst_console.
%   Wraps run_tx_burst with interactive controls.  Start triggers a TX
%   run (USRP or dry-run); Stop sets a flag that run_tx_burst's uiCtx
%   checks each iteration.  Progress label refreshes while running.
%
%   The TX loop still runs in the same MATLAB thread; UI stays alive
%   because run_tx_burst calls back into ui_progress() each iter, which
%   calls drawnow limitrate (capped to ~20 fps so it doesn't choke the
%   USRP feed).
%
%   Extras vs the v1 sketch:
%     - "Mode sweep" text field: comma-separated extras to run after the
%       primary dropdown selection (e.g. "9,10,11" -> runs 4 modes back
%       to back, returning to UI between each)
%     - "Save / Load preset" buttons: persist UI state to/from .mat
%     - "Snapshot" button: dump every open figure as PNG to a timestamped
%       folder, so you can capture spectrum/timescope/constellation along
%       with the app window in one click

    addpath(genpath(fileparts(mfilename('fullpath'))));

    % ---- figure ------------------------------------------------------
    fig = uifigure('Name', 'Burst TX Lab', 'Position', [120 60 520 720]);
    setappdata(fig, 'running',       false);
    setappdata(fig, 'stopRequested', false);

    gl = uigridlayout(fig, [14 2]);
    gl.RowHeight   = repmat({'fit'}, 1, 14);
    gl.ColumnWidth = {170, '1x'};
    gl.RowSpacing  = 6;
    gl.Padding     = [12 12 12 12];

    % ---- mode dropdown (populated from mode_registry) ----------------
    modes      = mode_registry();
    modeItems  = cell(1, numel(modes));
    modeIdData = zeros(1, numel(modes));
    for i = 1:numel(modes)
        modeItems{i}  = sprintf('%d  %s', modes{i}.id, modes{i}.todo);
        modeIdData(i) = modes{i}.id;
    end
    defBurst = default_burst_opts();

    uilabel(gl, 'Text', 'Jammer mode (primary):');
    ddMode = uidropdown(gl, 'Items', modeItems, 'ItemsData', modeIdData, ...
                            'Value', 8);

    % ---- mode sweep extras ------------------------------------------
    uilabel(gl, 'Text', 'Mode sweep (extras):');
    efSweep = uieditfield(gl, 'text', ...
        'Placeholder', 'e.g. 9,10,11 (blank = primary only)');

    % ---- jammer pattern ---------------------------------------------
    uilabel(gl, 'Text', 'Pattern:');
    ddPattern = uidropdown(gl, ...
        'Items', {'continuous','periodic','random','random_bursts','single_shot'}, ...
        'Value', defBurst.jammerPattern);

    % ---- integer spinners -------------------------------------------
    spFramesPerBurst   = add_spinner(gl, 'framesPerBurst:',       defBurst.framesPerBurst,      [1 100000]);
    spTxPeriodFrames   = add_spinner(gl, 'txPeriodFrames:',       defBurst.txPeriodFrames,      [1 100000]);
    spNumBursts        = add_spinner(gl, 'numBursts:',            defBurst.numBursts,           [1 100000]);
    spSingleShotBurst  = add_spinner(gl, 'singleShotBurst:',      defBurst.singleShotBurst,     [1 100000]);
    spDelayBeforeStart = add_spinner(gl, 'delayBeforeStart (s):', defBurst.delayBeforeStartSec, [0 600]);

    % ---- power slider with live value readout -----------------------
    uilabel(gl, 'Text', 'jam_power_scale:');
    powerRow = uigridlayout(gl, [1 2]);
    powerRow.ColumnWidth = {'1x', 50};
    powerRow.ColumnSpacing = 8;
    powerRow.Padding = [0 0 0 0];
    slPower  = uislider(powerRow, 'Limits', [0 2], 'Value', 1.0);
    lblPower = uilabel(powerRow, 'Text', '1.00');
    slPower.ValueChangingFcn = @(s,e) set(lblPower, 'Text', sprintf('%.2f', e.Value));
    slPower.ValueChangedFcn  = @(s,e) set(lblPower, 'Text', sprintf('%.2f', s.Value));

    % ---- dry run checkbox -------------------------------------------
    uilabel(gl, 'Text', '');
    cbDryRun = uicheckbox(gl, 'Text', 'Dry run (simulate, no USRP)', 'Value', false);

    % ---- preset + snapshot row --------------------------------------
    uilabel(gl, 'Text', '');
    miscRow = uigridlayout(gl, [1 3]);
    miscRow.ColumnSpacing = 8;
    miscRow.Padding = [0 0 0 0];
    btnSave = uibutton(miscRow, 'Text', 'Save preset...');
    btnLoad = uibutton(miscRow, 'Text', 'Load preset...');
    btnSnap = uibutton(miscRow, 'Text', '📸 Snapshot');

    % ---- start / stop buttons ---------------------------------------
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

    % ---- status + progress labels -----------------------------------
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
            modeList = build_mode_list();
            for k = 1:numel(modeList)
                if getappdata(fig, 'stopRequested'), break; end
                m = modeList(k);
                if numel(modeList) > 1
                    lblStatus.Text = sprintf('sweep %d/%d: mode %d', ...
                                             k, numel(modeList), m);
                    drawnow;
                end
                run_one_mode(m);
            end
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

    function modeList = build_mode_list()
        modeList = ddMode.Value;
        extrasStr = strtrim(efSweep.Value);
        if ~isempty(extrasStr)
            % accept "8,9,10" or "8 9 10" or "8, 9, 10"
            tokens = regexp(extrasStr, '[\s,]+', 'split');
            extras = zeros(1, 0);
            for i = 1:numel(tokens)
                if isempty(tokens{i}), continue; end
                v = str2double(tokens{i});
                if isnan(v)
                    error('Could not parse mode-sweep entry "%s"', tokens{i});
                end
                extras(end+1) = v; %#ok<AGROW>
            end
            modeList = unique([modeList, extras], 'stable');
        end
    end

    function run_one_mode(modeId)
        burst = defBurst;
        burst.framesPerBurst      = spFramesPerBurst.Value;
        burst.txPeriodFrames      = spTxPeriodFrames.Value;
        burst.numBursts           = spNumBursts.Value;
        burst.singleShotBurst     = spSingleShotBurst.Value;
        burst.delayBeforeStartSec = spDelayBeforeStart.Value;
        burst.jammerPattern       = ddPattern.Value;

        power  = slPower.Value;
        dryRun = cbDryRun.Value;

        params = load_parameters();
        params.knob.noise_power     = power;
        params.knob.jam_power_scale = power;

        sched = mode_registry('schedule', params, modeId);
        if isempty(sched)
            error('No schedule entry for mode %d.', modeId);
        end
        phase = sched(1);

        uiCtx = struct( ...
            'shouldStop', @() getappdata(fig, 'stopRequested'), ...
            'onProgress', @(iter, bIdx, ur) ui_progress(iter, bIdx, ur, burst.numBursts));

        if dryRun
            run_dry(params, burst, phase, uiCtx);
        else
            tx = init_usrp_tx(params);
            cleanupObj = onCleanup(@() safe_release(tx)); %#ok<NASGU>
            run_tx_burst(params, burst, phase, tx, uiCtx);
        end
    end

    function ui_progress(iter, burstIdx, underrunCnt, totalBursts)
        persistent lastTic
        if isempty(lastTic), lastTic = tic; end
        if toc(lastTic) < 0.05, return; end
        lastTic = tic;

        lblProgress.Text = sprintf( ...
            'Burst %d / %d    frames sent: %d    underruns: %d', ...
            burstIdx, totalBursts, iter, underrunCnt);
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
        preset.modeId             = ddMode.Value;
        preset.sweepExtras        = efSweep.Value;
        preset.jammerPattern      = ddPattern.Value;
        preset.framesPerBurst     = spFramesPerBurst.Value;
        preset.txPeriodFrames     = spTxPeriodFrames.Value;
        preset.numBursts          = spNumBursts.Value;
        preset.singleShotBurst    = spSingleShotBurst.Value;
        preset.delayBeforeStartSec= spDelayBeforeStart.Value;
        preset.jamPowerScale      = slPower.Value;
        preset.dryRun             = cbDryRun.Value;
    end

    function apply_preset(p)
        if isfield(p,'modeId') && ismember(p.modeId, modeIdData)
            ddMode.Value = p.modeId;
        end
        if isfield(p,'sweepExtras'),         efSweep.Value            = p.sweepExtras;          end
        if isfield(p,'jammerPattern')
            try, ddPattern.Value = p.jammerPattern; catch, end
        end
        if isfield(p,'framesPerBurst'),      spFramesPerBurst.Value   = p.framesPerBurst;       end
        if isfield(p,'txPeriodFrames'),      spTxPeriodFrames.Value   = p.txPeriodFrames;       end
        if isfield(p,'numBursts'),           spNumBursts.Value        = p.numBursts;            end
        if isfield(p,'singleShotBurst'),     spSingleShotBurst.Value  = p.singleShotBurst;      end
        if isfield(p,'delayBeforeStartSec'), spDelayBeforeStart.Value = p.delayBeforeStartSec;  end
        if isfield(p,'jamPowerScale')
            slPower.Value = max(slPower.Limits(1), min(slPower.Limits(2), p.jamPowerScale));
            lblPower.Text = sprintf('%.2f', slPower.Value);
        end
        if isfield(p,'dryRun'),              cbDryRun.Value           = logical(p.dryRun);      end
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

function run_dry(params, burst, phase, uiCtx)
% run_dry  Stand-in for run_tx_burst that needs no USRP.  Walks the
% burst timeline at 10x real speed so you can verify the UI without
% hardware (Start/Stop responsiveness, progress label progression,
% validation errors).  Does NOT exercise jammer waveform code.

    spec = params.spec;
    [real_frame, ~, ~] = build_frame(spec);
    framePeriodSec  = length(real_frame) / params.tx.fs;
    sleepPerIter    = max(framePeriodSec / 10, 0.001);

    if burst.runSeconds > 0
        stopMode = 'time';   stopAt = burst.runSeconds / 10;
    else
        stopMode = 'bursts'; stopAt = burst.numBursts * burst.txPeriodFrames;
    end

    fprintf('[dry] mode=%d pattern=%s  framesPerBurst=%d txPeriodFrames=%d numBursts=%d\n', ...
            phase.mode, burst.jammerPattern, burst.framesPerBurst, ...
            burst.txPeriodFrames, burst.numBursts);

    if burst.delayBeforeStartSec > 0
        t_d = tic;
        while toc(t_d) < (burst.delayBeforeStartSec / 10)
            if uiCtx.shouldStop(), return; end
            pause(0.05);
        end
    end

    t0 = tic; iter = 0; underrunCnt = 0; lastBurst = -1;
    while keep_dry(t0, iter, stopMode, stopAt)
        if uiCtx.shouldStop(), break; end
        iter     = iter + 1;
        frameIdx = iter - 1;
        burstIdx = floor(frameIdx / burst.txPeriodFrames) + 1;
        if burstIdx ~= lastBurst
            lastBurst = burstIdx;
            fprintf('[dry] burst %d starts (sim %.2fs)\n', burstIdx, toc(t0));
        end
        pause(sleepPerIter);
        uiCtx.onProgress(iter, burstIdx, underrunCnt);
    end
    fprintf('[dry] complete. iters=%d\n', iter);
end

function go = keep_dry(t0, iter, stopMode, stopAt)
    switch stopMode
        case 'time',   go = toc(t0) < stopAt;
        case 'bursts', go = iter < stopAt;
        otherwise,     go = false;
    end
end
