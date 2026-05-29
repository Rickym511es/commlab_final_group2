function Y = ofdm_demod_symbol(seg, FFT_size, cp_size)
% ofdm_demod_symbol  Strip CP and FFT one OFDM symbol; return shifted spectrum.
    Y = fftshift(fft(seg(cp_size+1:end), FFT_size));
end
