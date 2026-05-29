function m = mode03_fine_cfo()
% mode03_fine_cfo  TODO4 - attack LTS for fine CFO.
%   Attacks ONLY copy1 of LTS so RX can estimate channel from clean copy2,
%   isolating the fine-CFO effect. Fine CFO falls out of conj(copy1).*copy2.
    m.id    = 3;
    m.todo  = 'TODO4 LTS 細 CFO 攻擊';
    m.types = [1 2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @rxcfg;
end

function jammer = build(jam_type, ~, tx_signal, info, fs, knob)
    N = length(tx_signal); jammer = zeros(N,1);
    tx_rms = rms(tx_signal);
    copy1_start = info.lts_start + 32;
    copy1_end   = copy1_start + info.FFT_size - 1;
    idx = copy1_start : copy1_end;
    if jam_type == 1
        jammer(idx) = knob.noise_power * tx_rms * cnoise(numel(idx));
    else
        lts_full = gen_lts();
        lts_body = lts_full(33:96);
        lts_body = lts_body / rms(lts_body);
        n_lts = (0:length(lts_body)-1).';
        lts_attack = lts_body .* exp(1j*2*pi*knob.fine_cfo_hz*n_lts/fs);
        jammer(idx) = knob.jam_power_scale * tx_rms * lts_attack;
    end
end

function opt = rxcfg(opt, params)
    if params.sched.attackedLtsCopy == 1
        opt.ltsCopyForH = 2;
    else
        opt.ltsCopyForH = 1;
    end
    opt.modeLabel = sprintf('H from LTS copy %d (clean), fineCFO under test', ...
                            opt.ltsCopyForH);
end

function n = cnoise(k)
    n = (randn(k,1) + 1j*randn(k,1)) / sqrt(2);
end
