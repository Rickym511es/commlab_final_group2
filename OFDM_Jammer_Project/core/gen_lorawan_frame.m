function [phyPayload, fields] = gen_lorawan_frame(opts)
% gen_lorawan_frame  Build a LoRaWAN 1.0.x data PHYPayload.
%
%   [phyPayload, fields] = gen_lorawan_frame()
%   [phyPayload, fields] = gen_lorawan_frame(opts)
%
% Default output is an unconfirmed uplink frame:
%   PHYPayload = MHDR | FHDR | FPort | encrypted FRMPayload | MIC
%
% Useful opts fields:
%   mType     : 'UnconfirmedDataUp' (default), 'ConfirmedDataUp',
%               'UnconfirmedDataDown', 'ConfirmedDataDown'
%   devAddr   : 4-byte hex string in normal display order, e.g. '26011BDA'
%   fCnt      : 32-bit frame counter. Low 16 bits are carried in FHDR.
%   fPort     : 0..255. FPort 0 uses NwkSKey for payload encryption.
%   payload   : uint8 vector, char/string text, or hex string when payloadIsHex=true
%   nwkSKey   : 16-byte hex string or uint8 vector
%   appSKey   : 16-byte hex string or uint8 vector
%   fOpts     : MAC command bytes in FHDR, max 15 bytes
%
% Notes:
%   DevAddr and FCnt are serialized little-endian on air.
%   FRMPayload encryption and MIC follow LoRaWAN 1.0.x AES-128 rules.

    if nargin < 1 || isempty(opts)
        opts = struct();
    end

    opts = fill_defaults(opts);

    [mhdr, dir] = make_mhdr(opts.mType);
    devAddrLE = parse_devaddr_le(opts.devAddr);
    nwkSKey = parse_fixed_bytes(opts.nwkSKey, 16, 'nwkSKey');
    appSKey = parse_fixed_bytes(opts.appSKey, 16, 'appSKey');
    fOpts = parse_bytes(opts.fOpts, false);
    payload = parse_bytes(opts.payload, opts.payloadIsHex);

    if numel(fOpts) > 15
        error('gen_lorawan_frame:fOptsTooLong', 'FOpts must be 15 bytes or fewer.');
    end

    fCtrl = make_fctrl(opts, numel(fOpts), dir);
    fCnt16LE = u16le(bitand(uint32(opts.fCnt), uint32(65535)));
    fhdr = [devAddrLE, fCtrl, fCnt16LE, fOpts];

    hasFPort = opts.includeFPort || ~isempty(payload);
    if hasFPort
        fPort = uint8(opts.fPort);
        if fPort == 0
            payloadKey = nwkSKey;
        else
            payloadKey = appSKey;
        end
        frmPayload = lorawan_payload_crypt(payloadKey, payload, dir, devAddrLE, opts.fCnt);
        macPayload = [fhdr, fPort, frmPayload];
    else
        fPort = uint8([]);
        frmPayload = uint8([]);
        macPayload = fhdr;
    end

    msg = [mhdr, macPayload];
    if numel(msg) > 255
        error('gen_lorawan_frame:FrameTooLong', 'LoRaWAN MIC B0 supports message length <= 255 bytes.');
    end

    mic = lorawan_mic(nwkSKey, msg, dir, devAddrLE, opts.fCnt);
    phyPayload = [msg, mic].';

    fields.mhdr = mhdr;
    fields.macPayload = macPayload.';
    fields.fhdr = fhdr.';
    fields.devAddrLE = devAddrLE.';
    fields.fCtrl = fCtrl;
    fields.fCnt16LE = fCnt16LE.';
    fields.fOpts = fOpts.';
    fields.fPort = fPort;
    fields.frmPayloadPlain = payload.';
    fields.frmPayload = frmPayload.';
    fields.mic = mic.';
    fields.hex = bytes_to_hex(phyPayload.');
    fields.bitsMsbFirst = bytes_to_bits(phyPayload, 'msb');
    fields.bitsLsbFirst = bytes_to_bits(phyPayload, 'lsb');

    if nargout == 0
        fprintf('LoRaWAN PHYPayload (%d bytes): %s\n', numel(phyPayload), fields.hex);
        fprintf('MHDR=%02X  FHDR=%s  FPort=%s  FRMPayload=%s  MIC=%s\n', ...
                mhdr, bytes_to_hex(fhdr), bytes_to_hex(fPort), ...
                bytes_to_hex(frmPayload), bytes_to_hex(mic));
        clear phyPayload fields
    end
end

function opts = fill_defaults(opts)
    defaults.mType = 'UnconfirmedDataUp';
    defaults.devAddr = '26011BDA';
    defaults.fCnt = uint32(1);
    defaults.fPort = uint8(1);
    defaults.payload = 'Hello LoRaWAN';
    defaults.payloadIsHex = false;
    defaults.nwkSKey = '2B7E151628AED2A6ABF7158809CF4F3C';
    defaults.appSKey = '00112233445566778899AABBCCDDEEFF';
    defaults.fOpts = uint8([]);
    defaults.includeFPort = false;
    defaults.fCtrl = [];
    defaults.adr = false;
    defaults.adrAckReq = false;
    defaults.ack = false;
    defaults.classB = false;
    defaults.fPending = false;

    names = fieldnames(defaults);
    for i = 1:numel(names)
        name = names{i};
        if ~isfield(opts, name) || isempty(opts.(name))
            opts.(name) = defaults.(name);
        end
    end
end

function [mhdr, dir] = make_mhdr(mType)
    if isnumeric(mType)
        m = uint8(mType);
    else
        key = regexprep(lower(char(mType)), '[^a-z0-9]', '');
        switch key
            case 'joinrequest'
                m = uint8(0);
            case 'joinaccept'
                m = uint8(1);
            case {'unconfirmeddataup', 'unconfirmedup', 'up'}
                m = uint8(2);
            case {'unconfirmeddatadown', 'unconfirmeddown', 'down'}
                m = uint8(3);
            case {'confirmeddataup', 'confirmedup'}
                m = uint8(4);
            case {'confirmeddatadown', 'confirmeddown'}
                m = uint8(5);
            otherwise
                error('gen_lorawan_frame:BadMType', 'Unsupported MType: %s', char(mType));
        end
    end

    if m == 2 || m == 4
        dir = uint8(0);
    elseif m == 3 || m == 5
        dir = uint8(1);
    else
        error('gen_lorawan_frame:BadMType', 'This helper builds data frames only.');
    end

    major = uint8(0);
    mhdr = uint8(bitor(bitshift(m, 5), major));
end

function fCtrl = make_fctrl(opts, fOptsLen, dir)
    if ~isempty(opts.fCtrl)
        fCtrl = uint8(opts.fCtrl);
        return
    end

    fCtrl = uint8(fOptsLen);
    if opts.adr
        fCtrl = bitor(fCtrl, uint8(128));
    end
    if dir == 0 && opts.adrAckReq
        fCtrl = bitor(fCtrl, uint8(64));
    end
    if opts.ack
        fCtrl = bitor(fCtrl, uint8(32));
    end
    if dir == 0 && opts.classB
        fCtrl = bitor(fCtrl, uint8(16));
    end
    if dir == 1 && opts.fPending
        fCtrl = bitor(fCtrl, uint8(16));
    end
end

function mic = lorawan_mic(nwkSKey, msg, dir, devAddrLE, fCnt)
    b0 = [uint8(73), zeros(1, 4, 'uint8'), uint8(dir), devAddrLE, ...
          u32le(fCnt), uint8(0), uint8(numel(msg))];
    cmac = aes128_cmac(nwkSKey, [b0, msg]);
    mic = cmac(1:4);
end

function out = lorawan_payload_crypt(key, payload, dir, devAddrLE, fCnt)
    payload = uint8(payload(:).');
    if isempty(payload)
        out = uint8([]);
        return
    end

    nBlocks = ceil(numel(payload) / 16);
    stream = zeros(1, nBlocks * 16, 'uint8');
    for i = 1:nBlocks
        a = [uint8(1), zeros(1, 4, 'uint8'), uint8(dir), devAddrLE, ...
             u32le(fCnt), uint8(0), uint8(i)];
        stream((i - 1) * 16 + (1:16)) = aes128_encrypt_block(key, a);
    end
    out = bitxor(payload, stream(1:numel(payload)));
end

function tag = aes128_cmac(key, msg)
    blockSize = 16;
    zeroBlock = zeros(1, blockSize, 'uint8');
    l = aes128_encrypt_block(key, zeroBlock);
    k1 = cmac_subkey(l);
    k2 = cmac_subkey(k1);

    msg = uint8(msg(:).');
    n = ceil(numel(msg) / blockSize);
    if n == 0
        n = 1;
    end

    completeLast = ~isempty(msg) && mod(numel(msg), blockSize) == 0;
    if completeLast
        last = bitxor(msg((n - 1) * blockSize + (1:blockSize)), k1);
    else
        lastBytes = msg((n - 1) * blockSize + 1:end);
        padded = [lastBytes, uint8(128), zeros(1, blockSize - numel(lastBytes) - 1, 'uint8')];
        last = bitxor(padded, k2);
    end

    x = zeroBlock;
    for i = 1:n-1
        block = msg((i - 1) * blockSize + (1:blockSize));
        x = aes128_encrypt_block(key, bitxor(x, block));
    end
    tag = aes128_encrypt_block(key, bitxor(x, last));
end

function subkey = cmac_subkey(block)
    carry = uint16(0);
    subkey = zeros(1, 16, 'uint8');
    for i = 16:-1:1
        value = uint16(block(i));
        subkey(i) = uint8(bitand(bitshift(value, 1) + carry, 255));
        carry = bitshift(value, -7);
    end
    if bitand(block(1), uint8(128)) ~= 0
        subkey(16) = bitxor(subkey(16), uint8(135));
    end
end

function encrypted = aes128_encrypt_block(key, block)
    key = uint8(key(:).');
    block = uint8(block(:).');
    if numel(key) ~= 16 || numel(block) ~= 16
        error('gen_lorawan_frame:AesBlockSize', 'AES-128 key and block must both be 16 bytes.');
    end

    cipher = javaMethod('getInstance', 'javax.crypto.Cipher', 'AES/ECB/NoPadding');
    keySpec = javaObject('javax.crypto.spec.SecretKeySpec', int8(key), 'AES');
    cipher.init(1, keySpec);
    encrypted = typecast(cipher.doFinal(int8(block)), 'uint8');
    encrypted = encrypted(:).';
end

function bytes = parse_devaddr_le(value)
    if isnumeric(value) && isscalar(value)
        bytes = u32le(value);
        return
    end

    bytes = parse_fixed_bytes(value, 4, 'devAddr');
    bytes = fliplr(bytes);
end

function bytes = parse_fixed_bytes(value, n, name)
    bytes = parse_bytes(value, true);
    if numel(bytes) ~= n
        error('gen_lorawan_frame:BadLength', '%s must be %d bytes.', name, n);
    end
end

function bytes = parse_bytes(value, isHex)
    if nargin < 2
        isHex = false;
    end

    if isa(value, 'string') && isscalar(value)
        value = char(value);
    end

    if ischar(value)
        if isHex
            txt = regexprep(value, '[^0-9A-Fa-f]', '');
            if mod(numel(txt), 2) ~= 0
                error('gen_lorawan_frame:BadHex', 'Hex strings must contain an even number of digits.');
            end
            bytes = uint8(sscanf(txt, '%2x').');
        else
            bytes = uint8(value);
        end
    elseif isnumeric(value) || islogical(value)
        bytes = uint8(value(:).');
    else
        error('gen_lorawan_frame:BadBytes', 'Expected bytes as uint8/numeric, char, string, or hex text.');
    end
end

function out = u16le(value)
    value = uint32(value);
    out = uint8([bitand(value, 255), bitand(bitshift(value, -8), 255)]);
end

function out = u32le(value)
    value = uint32(value);
    out = uint8([bitand(value, 255), bitand(bitshift(value, -8), 255), ...
                 bitand(bitshift(value, -16), 255), bitand(bitshift(value, -24), 255)]);
end

function hex = bytes_to_hex(bytes)
    bytes = uint8(bytes(:).');
    if isempty(bytes)
        hex = '';
        return
    end
    hex = upper(sprintf('%02X', bytes));
end

function bits = bytes_to_bits(bytes, order)
    bytes = uint8(bytes(:));
    bits = zeros(numel(bytes) * 8, 1);
    idx = 1;
    for i = 1:numel(bytes)
        if strcmpi(order, 'lsb')
            shifts = 0:7;
        else
            shifts = 7:-1:0;
        end
        for shift = shifts
            bits(idx) = double(bitand(bitshift(bytes(i), -shift), uint8(1)));
            idx = idx + 1;
        end
    end
end
