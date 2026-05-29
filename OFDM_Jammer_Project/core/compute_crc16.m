function crc_bits = compute_crc16(bits)
% compute_crc16  CRC-16-CCITT-FALSE.
%   poly = x^16 + x^12 + x^5 + 1 (0x1021), init = 0xFFFF,
%   MSB-first, no input/output reflection, no xorOut.
%   Returns a 16x1 column of bits (MSB first). Ported verbatim from jammer1.m.
    bits   = uint8(bits(:));
    crc    = uint32(hex2dec('FFFF'));
    poly   = uint32(hex2dec('1021'));
    mask16 = uint32(hex2dec('FFFF'));
    for i = 1:length(bits)
        topBit = bitand(bitshift(crc, -15), uint32(1));
        crc    = bitand(bitshift(crc, 1), mask16);
        if bitxor(topBit, uint32(bits(i)))
            crc = bitxor(crc, poly);
        end
    end
    crc_bits = zeros(16, 1);
    for k = 1:16
        crc_bits(k) = double(bitand(bitshift(crc, -(16 - k)), uint32(1)));
    end
end
