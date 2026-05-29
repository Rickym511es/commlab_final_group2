function [real_frame, info, refs] = build_frame(spec)
% build_frame  Assemble the on-air TX frame [pad; STS; LTS; data; pad] and
% return its region info plus the references RX needs for demod/BER:
%   refs.sts, refs.lts             (already normalized by rms for matched filter)
%   refs.tx_bits, refs.tx_data_syms, refs.pilot_syms, refs.lts_f_known,
%   refs.frame_len, refs.bits_per_frame
% The 0.7 peak normalization matches the TX-side clip protection so on-air
% behavior is identical to the old jam_tx.m.
    sts = gen_sts();
    lts = gen_lts();
    rng(spec.seed);
    [ofdm_data, tx_bits, tx_data_syms, pilot_syms] = ...
        gen_ofdm_data(spec.num_ofdm, spec.qam_num);
    pad = zeros(spec.pad_len, 1);
    real_frame = [pad; sts; lts; ofdm_data; pad];
    real_frame = 0.7 * real_frame / max(abs(real_frame));

    info = frame_info(spec, length(sts), length(lts));

    refs.sts            = sts / rms(sts);
    refs.lts            = lts / rms(lts);
    refs.tx_bits        = tx_bits;
    refs.tx_data_syms   = tx_data_syms;
    refs.pilot_syms     = pilot_syms;
    refs.lts_f_known    = fftshift(fft(lts(33:96)));
    refs.frame_len      = 2*spec.pad_len + length(sts) + length(lts) + length(ofdm_data);
    refs.bits_per_frame = spec.num_ofdm * length(spec.data_sc) * log2(spec.qam_num);
end
