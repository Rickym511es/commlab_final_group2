function [ofdm_data, tx_bits, tx_data_syms, pilot_syms, user_bits, crc_bits] = ...
            gen_ofdm_data(num_ofdm, qam_num, crc_len)
% gen_ofdm_data  Generate num_ofdm CP-prefixed OFDM symbols and return:
%   ofdm_data    - time-domain stream (column vector)
%   tx_bits      - log2(qam_num)*num_data_sc x num_ofdm bit matrix
%                  (this is the FULL payload, including CRC bits at the
%                   tail; rx_bits comparison stays bit-for-bit valid)
%   tx_data_syms - num_data_sc x num_ofdm QAM symbol matrix
%   pilot_syms   - num_pilot_sc x num_ofdm reference pilot matrix
%   user_bits    - the leading payload bits before CRC (user data)
%   crc_bits     - the trailing CRC-16 bits appended (column vector)
%
% Backwards-compatible signature: crc_len defaults to 0, in which case
% the function generates a uniformly random bit stream (no CRC). The
% real on-air frame (built from build_frame -> load_parameters) passes
% spec.crc_len so the last 16 bits of each frame carry CRC-16-CCITT
% over the leading user bits. Mode-side jammers that fabricate fake
% OFDM data (mode 6 CP attack, mode 12 fake frame) still call with the
% old 2-arg form -> random bits, no CRC, because their content is meant
% to be junk.

    if nargin < 3, crc_len = 0; end

    active_sc = [-26:-1 1:26]; pilot_sc = [-21 -7 7 21];
    data_sc   = setdiff(active_sc, pilot_sc);
    FFT_size  = 64; cp_size = 16;

    bits_per_symbol = length(data_sc) * log2(qam_num);
    total_bits      = bits_per_symbol * num_ofdm;
    if crc_len > total_bits
        error('gen_ofdm_data: crc_len (%d) exceeds frame capacity (%d).', ...
              crc_len, total_bits);
    end
    user_bits_count = total_bits - crc_len;

    user_bits = randi([0 1], user_bits_count, 1);
    if crc_len > 0
        crc_bits = compute_crc16(user_bits);
        if numel(crc_bits) ~= crc_len
            error('gen_ofdm_data: compute_crc16 returned %d bits, expected %d.', ...
                  numel(crc_bits), crc_len);
        end
        full_bits = [user_bits; crc_bits];
    else
        crc_bits = zeros(0,1);
        full_bits = user_bits;
    end

    % Reshape into per-OFDM-symbol columns so each symbol gets its own
    % chunk of bits_per_symbol bits.
    tx_bits = reshape(full_bits, bits_per_symbol, num_ofdm);

    tx_data_syms = zeros(length(data_sc), num_ofdm);
    pilot_syms   = zeros(length(pilot_sc), num_ofdm);
    ofdm_data    = zeros((FFT_size+cp_size)*num_ofdm, 1);

    sc2idx = @(k) k + FFT_size/2 + 1;
    for s = 1:num_ofdm
        db = tx_bits(:, s);
        ds = qammod(db, qam_num, 'InputType','bit','UnitAveragePower',true);

        pilot_bits = randi([0 1], length(pilot_sc), 1);
        ps = 2*pilot_bits - 1;

        Xc = zeros(FFT_size, 1);
        Xc(sc2idx(pilot_sc)) = ps;
        Xc(sc2idx(data_sc))  = ds;
        a    = ifft(ifftshift(Xc));
        x_cp = [a(end-cp_size+1:end); a];

        idx = (s-1)*(FFT_size+cp_size)+1 : s*(FFT_size+cp_size);
        ofdm_data(idx) = x_cp;
        tx_data_syms(:, s) = ds;
        pilot_syms(:, s)   = ps;
    end
end
