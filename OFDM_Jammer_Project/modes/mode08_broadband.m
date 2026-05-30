function m = mode08_broadband()
% mode08_broadband  TODO9 - full-band complex AWGN across the whole frame.
%   One single variant. Magnitude is the outer power knob
%   (knob.jam_power_scale, settable from tx_console(mode, power)).
%
%   Previously this mode had separate type-1/type-2 phases that produced
%   the same waveform, distinguished only by which scaling knob applied.
%   That duplication is gone now - if you want a louder/quieter broadband
%   jammer, just pass a different power.
    m.id    = 8;
    m.todo  = 'TODO9 Broadband Constant Jamming';
    m.types = [2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(~, ~, tx_signal, ~, ~, ~)
    N = length(tx_signal);
    jammer = (randn(N,1) + 1j*randn(N,1)) / sqrt(2);
end
