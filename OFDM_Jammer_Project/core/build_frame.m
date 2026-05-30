function [real_frame, info, refs] = build_frame(spec)
% build_frame  Assemble the on-air TX frame [pad; STS; LTS; data; pad]
% and return its region info plus the references RX needs for demod,
% BER and CRC validation:
%   refs.sts, refs.lts             (already normalized by rms for matched filter)
%   refs.tx_bits, refs.tx_data_syms, refs.pilot_syms, refs.lts_f_known
%   refs.frame_len, refs.bits_per_frame
%   refs.user_bits, refs.crc_bits   (split form: payload vs CRC tail)
%
% The 0.7 peak normalization mirrors the original on-air clip protection,
% so behavior matches the pre-CRC jam_experiment baseline.
    sts = gen_sts();
    lts = gen_lts();
    rng(spec.seed);
    [ofdm_data, tx_bits, tx_data_syms, pilot_syms, user_bits, crc_bits] = ...
        gen_ofdm_data(spec.num_ofdm, spec.qam_num, spec.crc_len);

    pad = zeros(spec.pad_len, 1);
    real_frame = [pad; sts; lts; ofdm_data; pad];
    real_frame = 0.7 * real_frame / max(abs(real_frame));

    info = frame_info(spec, length(sts), length(lts));

    refs.sts            = sts / rms(sts);
    refs.lts            = lts / rms(lts);
    refs.tx_bits        = tx_bits;
    refs.tx_data_syms   = tx_data_syms;
    refs.pilot_syms     = pilot_syms;
    refs.user_bits      = user_bits;
    refs.crc_bits       = crc_bits;
    refs.lts_f_known    = fftshift(fft(lts(33:96)));
    refs.frame_len      = 2*spec.pad_len + length(sts) + length(lts) + length(ofdm_data);
    refs.bits_per_frame = spec.num_ofdm * length(spec.data_sc) * log2(spec.qam_num);
end
