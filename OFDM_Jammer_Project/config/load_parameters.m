function params = load_parameters()
% load_parameters
%   Single source of truth for all runtime parameters used by both
%   tx_console.m and rx_console.m. Returns a struct with substructs:
%     params.spec    - OFDM/frame spec (must be identical TX/RX)
%     params.tx      - B210 transmitter hardware settings
%     params.rx      - N210 receiver hardware settings
%     params.sched   - schedule timing + sweep flags
%     params.detect  - RX detector + jamming-detection thresholds
%     params.knob    - power knobs + per-attack tunables
%
%   The two old scripts (jam_experiment/jam_tx.m, jam_monitor.m) hand-typed
%   these blocks separately. Centralizing here is what kills the "must
%   match exactly" hazard.

    % --- OFDM / frame spec (must match TX/RX exactly) ---
    spec.FFT_size  = 64;
    spec.cp_size   = 16;
    spec.active_sc = [-26:-1, 1:26];
    spec.pilot_sc  = [-21 -7 7 21];
    spec.data_sc   = setdiff(spec.active_sc, spec.pilot_sc);
    spec.qam_num   = 16;
    spec.num_ofdm  = 20;
    spec.pad_len   = 200;
    spec.seed      = 12345;
    spec.crc_len   = 16;
    spec.data_bits_per_frame = spec.num_ofdm * length(spec.data_sc) * ...
                               log2(spec.qam_num) - spec.crc_len;
    params.spec = spec;

    % --- TX hardware (B210) ---
    tx.serialNum       = '34D9DC3';
    tx.platform        = 'B210';
    tx.fc              = 885e6;
    tx.fs              = 1e6;
    tx.masterClockRate = 20e6;
    tx.interpFactor    = tx.masterClockRate / tx.fs;
    tx.gain            = 15;
    tx.channelMapping  = [1 2];
    tx.liveDisplay     = true;
    tx.displayEvery    = 20;
    params.tx = tx;

    % --- RX hardware (N210) ---
    rx.platform        = 'N200/N210/USRP2';
    rx.ipAddress       = '192.168.10.2';
    rx.fc              = 885e6;
    rx.fs              = 1e6;
    rx.gain            = 30;
    rx.samplesPerFrame = 8192;
    rx.deci            = 100e6 / rx.fs;
    rx.displayEvery    = 5;
    params.rx = rx;

    % --- Schedule ---
    sched.secondsPerPhase = 20;
    sched.runBothTypes    = true;     % true: sweep all allowed types per mode
    sched.jamType         = 2;        % used when runBothTypes=false
    sched.runSeconds      = 480;      % RX total monitor duration
    sched.calibSeconds    = 6;
    sched.attackedLtsCopy = 1;        % TX attacks this LTS copy in mode 3
    params.sched = sched;

    % --- Detector / jamming-detection thresholds ---
    detect.detectorMode      = 'autocorr';   % 'autocorr' | 'mf'
    detect.autocorrThreshold = 0.5;
    detect.detectRatio       = 8;
    detect.snrDropDb         = 3;
    detect.detRateJam        = 0.8;
    detect.berJam            = 1e-2;
    params.detect = detect;

    % --- Power knobs + per-attack tunables ---
    knob.noise_power      = 1;       % whole-frame RMS ratio for jam_type=1
    knob.jam_power_scale  = 1;       % whole-frame RMS ratio for jam_type=2
    knob.sts_fake_shift   = 64;      % mode 1: fake STS sample offset
    knob.coarse_cfo_hz    = 80e3;    % mode 2: STS injected CFO
    knob.fine_cfo_hz      = 120e3;   % mode 3: LTS copy1 injected CFO
    knob.pilot_cfo_hz     = 60e3;    % mode 4: data CFO via pilots
    knob.flower_petals    = 6;       % mode 7: flower constellation petals
    knob.awgn_bw_ratio    = [0.2, 0.5, 1.0];   % mode 9 bandwidth sweep
    knob.single_tone_freq = 100e3;             % mode 10
    knob.multi_tone_freqs = [50e3, 120e3, 200e3]; % mode 11
    knob.multi_tone_amps  = [1.0, 0.8, 0.6];   % mode 11
    params.knob = knob;
end
