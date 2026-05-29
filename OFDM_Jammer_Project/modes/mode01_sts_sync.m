function m = mode01_sts_sync()
% mode01_sts_sync  TODO2 - attack STS for timing synchronization.
%   type 1: flood STS region with noise (matched filter has no clean peak).
%   type 2: inject a fake STS shifted by knob.sts_fake_shift samples
%           (matched filter peaks on our copy and frame_start is wrong).
%   RX strategy: skip coarse CFO (STS is polluted), rely on LTS fine CFO.
    m.id    = 1;
    m.todo  = 'TODO2 STS 時間同步攻擊';
    m.types = [1 2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @rxcfg;
end

function jammer = build(jam_type, ~, tx_signal, info, ~, knob)
    N = length(tx_signal); jammer = zeros(N,1);
    tx_rms = rms(tx_signal);
    if jam_type == 1
        idx = info.sts_start : info.sts_end;
        jammer(idx) = knob.noise_power * tx_rms * cnoise(numel(idx));
    else
        sts = gen_sts(); sts = sts / rms(sts);
        fake_pos = info.sts_start + knob.sts_fake_shift;
        fake_end = fake_pos + length(sts) - 1;
        if fake_pos >= 1 && fake_end <= N
            idx = fake_pos:fake_end;
            jammer(idx) = knob.jam_power_scale * tx_rms * sts;
        end
    end
end

function opt = rxcfg(opt, ~)
    opt.doCoarseCFO = false;
    opt.modeLabel   = 'no coarseCFO (STS attacked)';
end

function n = cnoise(k)
    n = (randn(k,1) + 1j*randn(k,1)) / sqrt(2);
end
