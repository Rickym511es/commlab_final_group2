function update_dashboard(dash, statusTxt, statusCol, frames, detRate, ber, snr, baseSNR, tput)
% update_dashboard  Refresh the status banner and 6 metric strings.
    dash.statusBox.FaceColor = statusCol;
    dash.status.String = statusTxt;
    dash.val(1).String = sprintf('%d', frames);
    dash.val(2).String = sprintf('%.0f %%', 100*detRate);
    if isnan(ber),  dash.val(3).String = '--';
    else,           dash.val(3).String = sprintf('%.2e', ber); end
    if isnan(snr),  dash.val(4).String = '--';
    else,           dash.val(4).String = sprintf('%.1f dB', snr); end
    if isnan(baseSNR), dash.val(5).String = '--';
    else,              dash.val(5).String = sprintf('%.1f dB', baseSNR); end
    dash.val(6).String = sprintf('%.1f kbps', tput);
    drawnow limitrate;
end
