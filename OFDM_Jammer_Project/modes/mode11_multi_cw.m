function m = mode11_multi_cw()
% mode11_multi_cw  TODO11 - sum of CW tones at knob.multi_tone_freqs with
% amplitudes knob.multi_tone_amps. RMS-normalized before whole-frame scaling.
    m.id    = 11;
    m.todo  = 'TODO11 多頻 CW';
    m.types = [2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(~, ~, tx_signal, ~, fs, knob)
    N = length(tx_signal);
    tx_rms = rms(tx_signal);
    t = (0:N-1)' / fs;
    multi_tone = zeros(N, 1);
    for k = 1:length(knob.multi_tone_freqs)
        multi_tone = multi_tone + ...
            knob.multi_tone_amps(k) * exp(1j*2*pi*knob.multi_tone_freqs(k)*t);
    end
    multi_tone = multi_tone / rms(multi_tone);
    jammer = knob.jam_power_scale * tx_rms * multi_tone;
end
