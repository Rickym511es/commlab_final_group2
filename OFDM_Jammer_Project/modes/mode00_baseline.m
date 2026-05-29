function m = mode00_baseline()
% mode00_baseline  No attack. jammer is all zeros.
    m.id    = 0;
    m.todo  = 'NO ATTACK (baseline)';
    m.types = [0];           % single phase: jam_type recorded as 0
    m.sweep = '';
    m.build = @build;
    m.rxcfg = @(opt, p) opt;
end

function jammer = build(~, ~, tx_signal, ~, ~, ~)
    jammer = zeros(length(tx_signal), 1);
end
