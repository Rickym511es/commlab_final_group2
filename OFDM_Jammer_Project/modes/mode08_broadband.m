function m = mode08_broadband()
% mode08_broadband  TODO9 - constant broadband (full-band) complex AWGN.
%   Whole-frame jammer; energy controlled by the final RMS normalize step.
    m.id    = 8;
    m.todo  = 'TODO9 Broadband Constant Jamming';
    m.types = [1 2];
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(~, ~, tx_signal, ~, ~, ~)
    N = length(tx_signal);
    jammer = (randn(N,1) + 1j*randn(N,1)) / sqrt(2);
end
