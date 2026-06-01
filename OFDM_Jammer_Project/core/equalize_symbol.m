function x = equalize_symbol(Y, H)
% equalize_symbol  Per-subcarrier equalize with MMSE-style regularization.
%
%   x[k] = Y[k] * conj(H[k]) / (|H[k]|^2 + epsilon)
%
% For strong subcarriers (|H[k]|^2 >> epsilon) this collapses to plain
% zero-forcing x = Y / H. For near-zero subcarriers the output is bounded
% by Y * conj(H) / epsilon ~ 0, which avoids the catastrophic explosion
% that zero-forcing produces when channel estimation gives H[k] ~ 0.
%
% That failure mode is exactly what mode 5 TODO6 type-2 induces: a fake
% LTS with every-other active subcarrier sign-inverted causes Y[k] ~ 0
% on the cancelled bins. With ZF, those bins amplify to infinity and
% destroy the per-symbol normalization in process_capture. With MMSE
% regularization they are treated as soft erasures - the legitimate bins
% are demapped correctly and only the cancelled half degrades to ~random.
%
% epsilon is chosen relative to the median |H| so the regularization
% adapts to whatever channel strength the LTS estimate produced; bins at
% <10% of median magnitude are heavily suppressed.

    Y(~isfinite(Y)) = 0;
    H(~isfinite(H)) = 0;

    Hmag = abs(H);
    strong = Hmag > 1e-9;
    if any(strong)
        typical = median(Hmag(strong));
    else
        typical = 1;
    end
    if ~isfinite(typical) || typical < 1e-9
        typical = 1;
    end
    eps_reg = (0.1 * typical)^2;

    x = Y .* conj(H) ./ (Hmag.^2 + eps_reg);
    x(~isfinite(x)) = 0;
end
