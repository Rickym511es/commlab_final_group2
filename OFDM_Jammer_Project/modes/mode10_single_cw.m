function m = mode10_single_cw()
% mode10_single_cw  TODO10 - single continuous-wave tone at knob.single_tone_freq.
    m.id    = 10;
    m.todo  = 'TODO10 單頻 CW';
    m.types = [2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(~, ~, tx_signal, ~, fs, knob)
    N = length(tx_signal);
    tx_rms = rms(tx_signal);
    t = (0:N-1)' / fs;
    single_tone = exp(1j*2*pi*knob.single_tone_freq * t);
    jammer = knob.jam_power_scale * tx_rms * single_tone;
end
