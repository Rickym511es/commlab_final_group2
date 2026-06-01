function selftest_3node(jsr_dB, cfo_hz, seed)
% selftest_3node  Offline (no-radio) check of the 3-node topology.
%
%   selftest_3node()                 jsr=6 dB, cfo=2 kHz, seed=7
%   selftest_3node(jsr_dB)           set jam-to-signal ratio at B
%   selftest_3node(jsr_dB, cfo_hz)   set C's CFO relative to A
%   selftest_3node(jsr_dB, cfo_hz, seed)
%
%   Unlike the 2-node selftest (which adds the jammer to the frame at the
%   SAME sample index - perfect alignment), this simulates the over-air sum
%   at B from two INDEPENDENT radios:
%
%       rx_B = [pad; A_frame; pad] + g_C * cfo(jammer, df) placed at a
%              RANDOM offset tau_C, + AWGN
%
%   so the jammer is NOT sample-aligned to A's frame. Runs B's process_capture
%   per attack mode and prints detect/BER/SNR. Expectation: alignment-free
%   modes (8/9/10/11 + noise) still raise BER; structured modes (1-7,12)
%   degrade because their per-sample placement no longer lines up at B.

    add_paths_3node();
    if nargin < 1 || isempty(jsr_dB), jsr_dB = 6;    end
    if nargin < 2 || isempty(cfo_hz), cfo_hz = 2e3;  end
    if nargin < 3 || isempty(seed),   seed   = 7;    end

    params = load_parameters_3node();
    rf = params.rf;  spec = rf.spec;  fs = rf.fs;
    [real_frame, info, refs] = build_frame(spec);
    frame_len = length(real_frame);

    leadPad = 300;                 % A frame position in B's capture
    capLen  = leadPad + frame_len + 600;
    g_lin   = 10^(jsr_dB/20);

    rxOpt = default_rxcfg(params);  rxOpt.modeLabel = 'victim';

    modes = mode_registry('modes');
    fprintf('\nselftest_3node: JSR=%g dB, C-CFO=%g Hz, seed=%d (INDEPENDENT jammer)\n\n', ...
            jsr_dB, cfo_hz, seed);
    fprintf('%-3s %-34s %-9s %-7s %-9s %-8s\n', 'id','attack','detected','score','BER','SNRdB');
    fprintf('%s\n', repmat('-', 1, 80));

    % --- clean baseline (no jammer) ---
    print_row(-1, 'CLEAN A->B (no jammer)', ...
        run_B(place(real_frame, leadPad, capLen), refs, spec, fs, params, rxOpt));

    for i = 1:numel(modes)
        m = modes{i};
        rng(1000 + 17*i + seed);   % reproducible per mode

        % build jammer (prefer structured type 2, else first allowed type)
        jt = pick_type(m);
        jam = m.build(jt, 1, real_frame, info, fs, params.knob);
        if jt ~= 0
            jam = normalize_jammer(jam, real_frame, jt, params.knob);
        end
        if max(abs(jam)) > 1e-12
            jam = jam * (g_lin * rms(real_frame) / (rms(jam)+eps));   % set JSR
        end
        % independent impairments: random timing offset + CFO
        tau_C = randi([-round(frame_len/3), round(frame_len/3)]);
        n = (0:length(jam)-1).';
        jam = jam .* exp(1j*2*pi*cfo_hz*n/fs);

        capture = place(real_frame, leadPad, capLen) + ...
                  place(jam, leadPad + tau_C, capLen);
        capture = capture + 0.01*(randn(capLen,1)+1j*randn(capLen,1))/sqrt(2);

        print_row(m.id, m.todo, run_B(capture, refs, spec, fs, params, rxOpt));
    end
    fprintf(['\nReading: alignment-free modes (8/9/10/11 + noise) should show\n' ...
             'high BER / link loss; structured modes (1-7,12) degrade toward\n' ...
             'the clean baseline because their sample placement no longer\n' ...
             'aligns at B. This is the expected 3-node behavior.\n']);
end

% --- place a signal into a zero capture at 1-based offset ---
function y = place(x, off, capLen)
    y = zeros(capLen,1);
    i0 = max(1, off);
    i1 = min(capLen, off + length(x) - 1);
    if i1 < i0, return; end
    s0 = i0 - off + 1;
    y(i0:i1) = x(s0 : s0 + (i1-i0));
end

function res = run_B(capture, refs, spec, fs, params, rxOpt)
    res = process_capture(capture, refs.sts, refs.lts, refs.frame_len, spec, ...
              fs, refs.tx_bits, refs.tx_data_syms, refs.pilot_syms, ...
              refs.lts_f_known, params.detect.detectRatio, rxOpt);
end

function jt = pick_type(m)
    if isempty(m.types), jt = 0; return; end
    if any(m.types == 2), jt = 2; else, jt = m.types(1); end
end

function print_row(id, label, res)
    det = 'no'; if res.detected, det = 'yes'; end
    if isnan(res.ber),   berS = '  --   '; else, berS = sprintf('%.2e', res.ber); end
    if isnan(res.snr_dB),snrS = '  --  ';  else, snrS = sprintf('%6.2f', res.snr_dB); end
    if isnan(res.detect_score), scS='  --'; else, scS = sprintf('%6.2f', res.detect_score); end
    if length(label) > 34, label = [label(1:33) '|']; end
    fprintf('%-3d %-34s %-9s %-7s %-9s %-8s\n', id, label, det, scS, berS, snrS);
end
