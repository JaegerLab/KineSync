function events = detect_events(trace, mask, threshold, minInterval, nearZero)
%DETECT_EVENTS Calculate one paw/trace; indices always refer to original frames.
% events = Behav.detect_events(trace, mask, threshold, minInterval)
% events = Behav.detect_events(trace, mask, threshold, minInterval, nearZero)
%
%  trace:       paw x, y or speed, one value per frame
%  mask:        logical, false for excluded frames
%  threshold:   threshold, in the units of trace
%  minInterval: minimum distance between peaks/valleys (frames)
%  nearZero:    rest level for onset/offset (default NaN: none found)
% events: struct of frame indices: rising, falling, onset, offset, peak,
%        valley, masked (first frame of each masked period).
% See docs/functions.md.

if nargin<5, nearZero = NaN; end
trace = trace(:);
mask = logical(mask(:));
if numel(mask) ~= numel(trace), error('behav:maskSize', 'Mask and trace sizes differ.'); end
validateattributes(minInterval, {'numeric'}, {'scalar','integer','positive','finite'});
trace(~mask) = NaN;
events = struct('rising', [], 'falling', [], 'onset', [], 'offset', [], ...
    'peak', [], 'valley', [], 'masked', find(diff(~mask)==1)+1);
if ~isfinite(threshold) || ~any(isfinite(trace)), return; end
events.rising = find(trace(1:end-1)<=threshold & trace(2:end)>threshold);
events.falling = find(trace(1:end-1)>threshold & trace(2:end)<=threshold)+1;
onset = nan(size(events.rising));
offset = nan(size(events.falling));
% Onset/offset are searched back/forward to the neighbouring crossing.
for k = 1:numel(onset)
    f = events.rising(k);
    from = events.falling(find(events.falling <= f, 1, 'last'));
    if isempty(from), from = 1; end
    range = from:f;
    % Do not search across a masked/missing interval.
    gap = find(~isfinite(trace(range)), 1, 'last');
    if ~isempty(gap), range = range(gap+1:end); end
    j = find(trace(range) <= nearZero, 1, 'last');
    if ~isempty(j), onset(k) = range(j); end
end
for k = 1:numel(offset)
    f = events.falling(k);
    to = events.rising(find(events.rising >= f, 1, 'first'));
    if isempty(to), to = numel(trace); end
    range = f:to;
    gap = find(~isfinite(trace(range)), 1, 'first');
    if ~isempty(gap), range = range(1:gap-1); end
    j = find(trace(range) <= nearZero, 1, 'first');
    if ~isempty(j), offset(k) = range(j); end
end
events.onset = unique(onset(isfinite(onset)));
events.offset = unique(offset(isfinite(offset)));
% Process finite runs independently so peaks cannot bridge excluded periods.
finite = isfinite(trace);
d = diff([false; finite; false]);
starts = find(d==1); stops = find(d==-1)-1;
prominence = std(trace, 'omitnan');
for k = 1:numel(starts)
    range = starts(k):stops(k);
    if numel(range) < 3, continue; end
    distance = min(minInterval, numel(range)-2);
    [value, idx] = findpeaks(trace(range), 'MinPeakProminence', prominence, 'MinPeakDistance', distance);
    keep = value >= threshold;
    events.peak = [events.peak; starts(k)-1+idx(keep)]; %#ok<AGROW>
    
    [~, idx] = findpeaks(-trace(range), 'MinPeakProminence', prominence, 'MinPeakDistance', distance);
    idx = idx(trace(range(idx)) <= threshold);
    events.valley = [events.valley; starts(k)-1+idx]; %#ok<AGROW>
end
end
