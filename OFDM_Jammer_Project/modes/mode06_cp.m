function m = mode06_cp()
% mode06_cp  TODO7 - attack CP for circular convolution.
%   The CP makes linear channel convolution behave circularly inside the FFT.
%   Replacing each CP with non-matching content breaks circularity, which
%   under any multipath causes ISI -> bit flips.
%     type 1: noise replaces each CP.
%     type 2: each CP replaced with the START of an unrelated OFDM body.
    m.id    = 6;
    m.todo  = 'TODO7 CP 循環卷積攻擊';
    m.types = [1 2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(jam_type, ~, tx_signal, info, ~, knob)
    N = length(tx_signal); jammer = zeros(N,1);
    tx_rms = rms(tx_signal);
    if jam_type == 1
        for s = info.cp_starts(:).'
            idx = s : s + info.cp_size - 1;
            jammer(idx) = knob.noise_power * tx_rms * cnoise(info.cp_size);
        end
    else
        [fake_ofdm, ~, ~, ~] = gen_ofdm_data(info.num_ofdm_symbols, info.qam_num);
        fake_ofdm = fake_ofdm / rms(fake_ofdm);
        for k = 0:info.num_ofdm_symbols-1
            s          = info.cp_starts(k+1);
            body_start = k * info.sym_len + info.cp_size + 1;
            wrong_cp   = fake_ofdm(body_start : body_start + info.cp_size - 1);
            idx = s : s + info.cp_size - 1;
            jammer(idx) = knob.jam_power_scale * tx_rms * wrong_cp;
        end
    end
end

function n = cnoise(k)
    n = (randn(k,1) + 1j*randn(k,1)) / sqrt(2);
end
