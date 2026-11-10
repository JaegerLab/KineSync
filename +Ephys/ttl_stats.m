function [label, s] = ttl_stats(channel)
% [label, s] = Ephys.ttl_stats(channel)
% Pulse count, width and rate of one Ephys.ttl_channels channel.
%   s.number  rising edges
%   s.width   median pulse width (s), NaN without a complete pulse
%   s.freq    1 / median interval between rising edges (Hz), NaN under 2 pulses
%   label     e.g. 'DIN-00: 30900 TTL, 10 ms, 100 Hz' ('-' for NaN)
    rise = channel.rise(:);
    fall = channel.fall(:);
    s.number = numel(rise);
    % each pulse ends at the first falling edge after it
    s.width = NaN;
    if ~isempty(rise) && ~isempty(fall)
        [~, ~, next] = histcounts(rise, [-Inf; fall; Inf]);
        ended = next <= numel(fall);
        if any(ended), s.width = median(fall(next(ended)) - rise(ended)); end
    end
    intervals = diff(rise);
    intervals = intervals(isfinite(intervals) & intervals > 0);
    s.freq = NaN;
    if ~isempty(intervals), s.freq = 1/median(intervals); end

    if isnan(s.width)
        width = '-';
    elseif s.width < 1
        width = sprintf('%.3g ms', 1000*s.width);
    else
        width = sprintf('%.3g s', s.width);
    end
    freq = '-';
    if ~isnan(s.freq), freq = sprintf('%.4g', s.freq); end
    label = sprintf('%s: %d TTL, %s, %s Hz', channel.name, s.number, width, freq);
end
