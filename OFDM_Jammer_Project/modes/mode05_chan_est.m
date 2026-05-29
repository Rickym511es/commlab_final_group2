function m = mode05_chan_est()
% mode05_chan_est  TODO6 - attack LTS for channel estimation.
%   type 1: noise on LTS region corrupts Y[k].
%   type 2: send a fake LTS with every other active subcarrier inverted so
%           estimated H is wrong on those bins.
%   RX strategy: disable fine CFO (LTS is polluted); coarse CFO from clean STS.
    m.id    = 5;
    m.todo  = 'TODO6 LTS 通道估計攻擊';
    m.types = [1 2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @rxcfg;
end

function jammer = build(jam_type, ~, tx_signal, info, ~, knob)
    N = length(tx_signal); jammer = zeros(N,1);
    tx_rms = rms(tx_signal);
    idx = info.lts_start : info.lts_end;
    if jam_type == 1
        jammer(idx) = knob.noise_power * tx_rms * cnoise(numel(idx));
    else
        FFT_size = info.FFT_size;
        lts_sc = -26:26;
        lts_val = [1, 1,-1,-1, 1, 1,-1, 1,-1, 1, 1, 1, 1, 1, 1, ...
                  -1,-1, 1, 1,-1, 1,-1, 1, 1, 1, 1, 0, 1,-1,-1, ...
                   1, 1,-1, 1,-1, 1,-1,-1,-1,-1,-1, 1, 1,-1,-1, ...
                   1,-1, 1,-1, 1, 1, 1, 1];
        mask = ones(size(lts_val)); mask(1:2:end) = -1;
        lts_f = zeros(FFT_size, 1);
        lts_f(lts_sc + FFT_size/2 + 1) = lts_val .* mask;
        lts_body = ifft(ifftshift(lts_f), FFT_size);
        lts_fake = [lts_body(end-31:end); lts_body; lts_body];
        lts_fake = lts_fake / rms(lts_fake);
        jammer(idx) = knob.jam_power_scale * tx_rms * lts_fake;
    end
end

function opt = rxcfg(opt, ~)
    opt.doFineCFO = false;
    opt.modeLabel = 'no fineCFO (LTS attacked), H under test';
end

function n = cnoise(k)
    n = (randn(k,1) + 1j*randn(k,1)) / sqrt(2);
end
