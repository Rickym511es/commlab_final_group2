function rxOpt = default_rxcfg(params)
% default_rxcfg  Baseline rxOpt used unless a mode's rxcfg modifies it.
    rxOpt.detectorMode      = params.detect.detectorMode;
    rxOpt.autocorrThreshold = params.detect.autocorrThreshold;
    rxOpt.doCoarseCFO       = true;
    rxOpt.doFineCFO         = true;
    rxOpt.ltsCopyForH       = 0;       % 0 = average both LTS copies
    rxOpt.modeLabel         = 'default';
end
