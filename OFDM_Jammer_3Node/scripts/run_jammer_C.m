function run_jammer_C(params)
% run_jammer_C  Node C reactive jammer loop (TDD listen-then-talk).
%
%   Builds the jammer waveform once from the chosen mode descriptor against a
%   REFERENCE frame (C knows A's waveform spec/seed, not A's on-air timing).
%   Then, on a single N210:
%     reactive=true  : sense A's preamble with the RX object; when the channel
%                      is busy, release RX, open TX, stream the jammer for
%                      jamBursts frames, release TX, sense again.
%     reactive=false : periodic duty cycle (dutyOnFrames on / rest off).
%
%   Only one System object touches the radio at a time (release between
%   sense and jam), so this works on a single half-duplex-in-MATLAB N210.

    rf = params.rf;  react = params.C.react;
    [real_frame, info, refs] = build_frame(rf.spec);
    frame_len = length(real_frame);

    % ---- build the jammer waveform once -------------------------------
    modes = mode_registry('modes');          % no params needed for 'modes'
    m = pick_mode(modes, react.jammerMode);
    jamType = react.jammerType;
    bw_idx  = 1;                              % mode 9 sweep index if any
    jammer  = m.build(jamType, bw_idx, real_frame, info, rf.fs, params.knob);
    if jamType ~= 0
        jammer = normalize_jammer(jammer, real_frame, jamType, params.knob);
    end
    jpk = max(abs(jammer));
    if jpk > 0.95, jammer = jammer * (0.95 / jpk); end
    txMat = jammer;                           % single channel
    zeroMat = zeros(frame_len, 1);

    fprintf('\nNode C jammer: mode %d (%s), type %d, reactive=%d\n', ...
            m.id, m.todo, jamType, react.reactive);
    fprintf('jam_rms/ref_rms = %.2f, peak = %.2f, frame_len = %d\n\n', ...
            rms(jammer)/max(rms(real_frame),1e-12), max(abs(jammer)), frame_len);

    % ---- construct both radio objects once (only one active at a time)-
    rx = init_n210_rx(params.C.rx, rf);
    tx = init_n210_tx(params.C.tx, rf);
    c  = onCleanup(@() c_cleanup(rx, tx));

    if react.reactive
        reactive_loop(params, rx, tx, txMat, refs, frame_len);
    else
        periodic_loop(params, tx, txMat, zeroMat);
    end
end

% ===================================================================
function reactive_loop(params, rx, tx, txMat, refs, frame_len)
    react = params.C.react;
    pad_len = params.rf.spec.pad_len;
    sts_len = length(refs.sts);
    try, release(tx); catch, end            % ensure RX can grab the radio
    fprintf('Reactive sensing... (Ctrl-C to stop)\n');

    t0 = tic; triggers = 0; senseRounds = 0;
    while true
        % ---- SENSE phase (RX active) ----
        senseRounds = senseRounds + 1;
        detScore = 0; busy = false; frameStart = 0;
        for k = 1:react.senseReads
            try, [data,len,~] = rx(); catch, len = 0; data = []; end
            if len == 0, continue; end
            det = detect_sts_autocorr(data, sts_len, pad_len, react.detectThresh);
            if det.score > detScore, detScore = det.score; frameStart = det.frame_start; end
            energyOK = (react.energyThresh <= 0) || (rms(data) > react.energyThresh);
            if det.detected && energyOK, busy = true; end
        end
        try, release(rx); catch, end        % free the radio for TX

        if ~busy
            fprintf('[%6.1fs] sense: idle (score=%.2f)\n', toc(t0), detScore);
            continue;
        end

        % ---- JAM phase (TX active) ----
        triggers = triggers + 1;
        burst = txMat;
        if react.alignToFrame && frameStart > 0      % coarse best-effort align
            burst = circshift(txMat, mod(frameStart-1, frame_len));
        end
        fprintf('[%6.1fs] A BUSY (score=%.2f) -> FIRE burst #%d (%d frames)\n', ...
                toc(t0), detScore, triggers, react.jamBursts);
        for b = 1:react.jamBursts
            try, tx(burst); catch ME
                fprintf('  C tx error: %s\n', ME.message); break;
            end
        end
        try, release(tx); catch, end        % free the radio for next sense
    end
end

% ===================================================================
function periodic_loop(params, tx, txMat, zeroMat)
    react = params.C.react;
    onF = react.dutyOnFrames; perF = max(react.dutyPeriodFrames, onF);
    fprintf('Periodic jammer: %d on / %d off frames (Ctrl-C to stop)\n', onF, perF-onF);
    iter = 0; t0 = tic;
    while true
        iter = iter + 1;
        pos = mod(iter-1, perF);
        out = txMat; if pos >= onF, out = zeroMat; end
        try, tx(out); catch ME
            fprintf('  C tx error: %s\n', ME.message); pause(0.1);
        end
        if mod(iter, 2000) == 0
            fprintf('[%6.1fs] C periodic frames=%d\n', toc(t0), iter);
        end
    end
end

% ===================================================================
function m = pick_mode(modes, id)
    m = [];
    for i = 1:numel(modes)
        if modes{i}.id == id, m = modes{i}; return; end
    end
    error('run_jammer_C: no mode with id %d (valid 0..12).', id);
end

function c_cleanup(rx, tx)
    try, release(rx); catch, end
    try, release(tx); catch, end
end
