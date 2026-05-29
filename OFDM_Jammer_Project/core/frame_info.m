function info = frame_info(spec, sts_len, lts_len)
% frame_info  Region index ranges for one assembled frame
%   [pad | STS | LTS | OFDM data | pad]. Used by build_jammer to align
%   per-region attacks and by RX to slice STS/LTS/data segments.
    pad = spec.pad_len;  FFT_size = spec.FFT_size;  cp = spec.cp_size;
    ns  = spec.num_ofdm; sym = FFT_size + cp;
    info.FFT_size         = FFT_size;
    info.cp_size          = cp;
    info.sym_len          = sym;
    info.num_ofdm_symbols = ns;
    info.qam_num          = spec.qam_num;
    info.sts_start        = pad + 1;
    info.sts_end          = info.sts_start + sts_len - 1;
    info.lts_start        = info.sts_end + 1;
    info.lts_end          = info.lts_start + lts_len - 1;
    info.lts_body_start   = info.lts_start + 32;
    info.data_start       = info.lts_end + 1;
    info.data_end         = info.data_start + ns*sym - 1;
    info.cp_starts        = info.data_start + (0:ns-1)*sym;
end
