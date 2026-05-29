function det = detect_sts_autocorr(data, sts_len, pad_len, threshold)
% detect_sts_autocorr  Schmidl-Cox |P|/R detector on the STS 16-sample period.
%   Sensitive to STS periodicity -> detection rate truly drops when STS is
%   noise-covered. Use this when you want the attack to manifest as missed
%   preamble (instead of just constellation spread under the matched filter).
    D = 16;
    L = sts_len - D;
    x = data(:); N = length(x);
    det.detected = false; det.frame_start = 0; det.score = 0;
    if N < L + D + 1, return; end

    prodSeq = conj(x(1:N-D)) .* x(1+D:N);
    pwrSeq  = abs(x(1+D:N)).^2;
    kernel  = ones(L, 1);
    Pseq = filter(kernel, 1, prodSeq);
    Rseq = filter(kernel, 1, pwrSeq);
    M = abs(Pseq) ./ (Rseq + 1e-12);

    [pkM, peak_idx] = max(M);
    det.score = pkM;
    if pkM < threshold, return; end

    sts_start_in_data = peak_idx - L + 1;
    det.frame_start   = sts_start_in_data - pad_len;
    if det.frame_start < 1, return; end
    det.detected = true;
end
