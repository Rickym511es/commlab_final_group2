function det = detect_sts_mf(data, sts, pad_len, detectRatio)
% detect_sts_mf  160-sample STS matched-filter detector.
%   Strong matched gain -> detection rate barely drops when STS is noise-
%   covered (attack shows as constellation spread instead).
    det.detected = false; det.frame_start = 0; det.score = 0;
    mf   = conj(flipud(sts(:)));
    corr = abs(conv(data, mf));
    [pk, peak_idx] = max(corr);
    noiseLvl = median(corr) + 1e-12;
    det.score = pk / noiseLvl;
    if det.score < detectRatio, return; end
    sts_start_in_data = peak_idx - length(sts) + 1;
    det.frame_start = sts_start_in_data - pad_len;
    if det.frame_start < 1, return; end
    det.detected = true;
end
