function x = equalize_symbol(Y, H)
% equalize_symbol  Zero-forcing equalize: x = Y ./ H on active subcarriers.
    x = zeros(size(Y));
    Y(~isfinite(Y)) = 0;  H(~isfinite(H)) = 0;
    v = abs(H) > 1e-6;
    x(v) = Y(v) ./ H(v);
    x(~isfinite(x)) = 0;
end
