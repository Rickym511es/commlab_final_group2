function m = mode02_coarse_cfo()
% mode02_coarse_cfo  TODO3 - attack STS coarse CFO.
%   Structured-only (type 2). A pure-noise variant would be indistinguishable
%   from mode 1's noise variant; the real attack is injecting an STS with a
%   deliberate CFO so RX folds the fake phase into its coarse CFO estimate.
%   RX strategy: leave coarse+fine CFO ON to actually test the coarse path.
    m.id    = 2;
    m.todo  = 'TODO3 STS 粗 CFO 攻擊';
    m.types = [2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @rxcfg;
end

function jammer = build(~, ~, tx_signal, info, fs, knob)
    N = length(tx_signal); jammer = zeros(N,1);
    tx_rms = rms(tx_signal);
    idx = info.sts_start : info.sts_end;
    sts = gen_sts(); sts = sts / rms(sts);
    n_sts = (0:length(sts)-1).';
    sts_attack = sts .* exp(1j*2*pi*knob.coarse_cfo_hz*n_sts/fs);
    jammer(idx) = knob.jam_power_scale * tx_rms * sts_attack;
end

function opt = rxcfg(opt, ~)
    opt.modeLabel = 'coarseCFO under test';
end
