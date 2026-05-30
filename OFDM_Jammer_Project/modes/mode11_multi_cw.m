function m = mode11_multi_cw()
% mode11_multi_cw  TODO11 - sum of CW tones at knob.multi_tone_freqs with
% amplitudes knob.multi_tone_amps. RMS-normalized before whole-frame scaling.
%
% Override the target frequencies (and amplitudes) at the console call site:
%   tx_console(11, 1, 'freqs', [80e3 160e3], 'amps', [1 1])
%
% If 'freqs' is given without 'amps', or amps is shorter than freqs, the
% missing amplitudes default to 1 so it's easy to pick freqs without caring
% about per-tone weights.
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
    freqs = knob.multi_tone_freqs(:).';
    amps  = knob.multi_tone_amps(:).';
    if numel(amps) < numel(freqs)
        amps = [amps, ones(1, numel(freqs) - numel(amps))];
    elseif numel(amps) > numel(freqs)
        amps = amps(1:numel(freqs));
    end
    t = (0:N-1)' / fs;
    multi_tone = zeros(N, 1);
    for k = 1:numel(freqs)
        multi_tone = multi_tone + amps(k) * exp(1j*2*pi*freqs(k)*t);
    end
    if rms(multi_tone) > 1e-12
        multi_tone = multi_tone / rms(multi_tone);
    end
    jammer = knob.jam_power_scale * tx_rms * multi_tone;
end
