function jammer = normalize_jammer(jammer, tx_signal, jam_type, knob)
% normalize_jammer  Whole-frame RMS normalize so that
%   rms(jammer) / rms(tx_signal) == active_knob (noise_power or jam_power_scale).
% Mirrors the final scaling step in the old jam_tx.build_jammer; applied
% centrally so each mode descriptor only has to shape the jammer.
    if jam_type == 1
        active_knob = knob.noise_power;
    else
        active_knob = knob.jam_power_scale;
    end
    tx_rms = rms(tx_signal);
    jr = rms(jammer);
    if jr > 1e-12 && active_knob > 0
        jammer = jammer * (active_knob * tx_rms / jr);
    end
end
