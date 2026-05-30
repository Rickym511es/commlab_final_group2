function selftest()
% selftest  Digital-loopback parity check for the OFDM_Jammer_Project refactor.
%
% For every scheduled phase (mode x type x bw_idx), builds the jammer from the
% mode descriptor, adds it to the real frame, and runs process_capture on the
% concatenation (with leading pad to simulate a streaming buffer). Prints
% detect score / BER / SNR per phase.
%
% Reproducible: rng is reseeded per phase from a fixed master seed so the
% random-noise-bearing modes (1/3/4/5/6/7/8/9) produce identical numbers
% across runs. Compare two runs (e.g. before/after a change) by diffing the
% printed lines.

    here = fileparts(mfilename('fullpath'));
    addpath(genpath(here));

    params = load_parameters();
    spec = params.spec;
    [real_frame, info, refs] = build_frame(spec);

    % Pad capture so frame_start search has room (process_capture expects
    % data length > frame_len + a leading buffer for STS detection).
    leadPad = 200;
    capLen  = leadPad + length(real_frame) + 200;

    sched = mode_registry('schedule', params);
    fprintf('selftest: %d phases\n\n', numel(sched));
    fprintf('%-3s %-42s %-10s %-7s %-9s %-7s %-4s\n', ...
            'idx', 'phase', 'detected', 'score', 'BER', 'SNRdB', 'CRC');
    fprintf('%s\n', repmat('-', 1, 95));

    for i = 1:numel(sched)
        s = sched(i);
        rng(424242 + 1000*i);   % per-phase reproducible seed
        jammer_short = s.descriptor.build(s.type, s.bw_idx, real_frame, info, ...
                                           params.tx.fs, params.knob);
        if s.type ~= 0
            jammer_short = normalize_jammer(jammer_short, real_frame, s.type, params.knob);
        end
        rx_frame = real_frame + jammer_short;
        capture = [zeros(leadPad,1); rx_frame; zeros(capLen - leadPad - length(rx_frame), 1)];

        rxOpt = default_rxcfg(params);
        rxOpt = s.descriptor.rxcfg(rxOpt, params);

        res = process_capture(capture, refs.sts, refs.lts, refs.frame_len, spec, ...
                              params.rx.fs, refs.tx_bits, refs.tx_data_syms, ...
                              refs.pilot_syms, refs.lts_f_known, ...
                              params.detect.detectRatio, rxOpt);

        det = ternary(res.detected, 'yes', 'no');
        ber = res.ber;   if isnan(ber), berStr = '  --   '; else, berStr = sprintf('%.2e', ber); end
        snr = res.snr_dB; if isnan(snr), snrStr = '  --   '; else, snrStr = sprintf('%6.2f', snr); end
        score = res.detect_score; if isnan(score), scoreStr = '  --'; else, scoreStr = sprintf('%6.2f', score); end
        if ~res.detected, crcStr = ' -- ';
        elseif res.crc_pass, crcStr = 'pass';
        else,                crcStr = 'fail'; end
        fprintf('%-3d %-42s %-10s %-7s %-9s %-7s %-4s\n', ...
                i, truncate(s.label, 42), det, scoreStr, berStr, snrStr, crcStr);
    end
    fprintf('\nselftest done.\n');
end

function s = truncate(s, n)
    if length(s) > n, s = [s(1:n-1) '…']; end
end

function out = ternary(c, a, b)
    if c, out = a; else, out = b; end
end
