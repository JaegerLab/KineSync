function [w, info] = auto_window_width(x, y, varargin)
%AUTO_WINDOW_WIDTH  Conservative segment width above which pose segments are trusted.
%
%   w = auto_window_width(x, y)
%   w = auto_window_width(x, y, thr)
%   [w, info] = auto_window_width(x, y, thr, Name, Value, ...)
%
%   Jumps (frame-to-frame displacement > thr) split the trace into
%   segments. DeepLabCut mislabels typically jump to a wrong body part,
%   stay for n frames, and jump back. This function finds those
%   out-and-back excursions, measures how long the error segments last,
%   and returns a width w (in data points) chosen so that segments of
%   length >= w are very unlikely to be errors. It deliberately errs on the
%   large side: short good segments may be rejected, long bad ones should
%   not be accepted.
%
%   If thr is omitted or empty, Pose.auto_jump_threshold(x, y) is called.
%
%   Algorithm
%   1. Jumps: J = frames where |displacement| > thr (or is NaN).
%   2. Excursions: starting from each jump i, add up the following jump
%      vectors. If the running sum returns close to zero within MaxJumps
%      jumps (|sum| < CancelTol * |jump i|), the label has come back to
%      where it left, so the segments in between are an excursion. A
%      multi-step excursion (wrong part A -> wrong part B -> back) is
%      caught as one excursion. Scanning is left to right, non-overlapping.
%   3. Home rule: an out-and-back pattern only says the inner segments
%      differ from their neighbours, not which side is wrong. A long good
%      segment between two errors at the same wrong spot looks the same.
%      So an excursion is accepted only if its duration is at most
%      HomeRatio times the longer of its two flanking segments ("the trip
%      is shorter than the home").
%   4. Width: q = Quantile of the lengths of all segments inside accepted
%      excursions (the error segments), then w = ceil(Margin * q).
%
%   Options
%     'CancelTol'  residual allowed when jumps cancel, as a fraction of the
%                  first jump's length (default 0.3)
%     'MaxJumps'   max jumps in one excursion, including the outgoing and
%                  return jump (default 6)
%     'HomeRatio'  see step 3 (default 2)
%     'Quantile'   quantile of error-segment lengths (default 0.99)
%     'Margin'     safety factor applied to that quantile (default 1.5)
%     'MinWidth'   lower bound on w (default 2)
%     'Plot'       true to show diagnostics (default false)
%
%   info fields
%     thr, thrSource         jump threshold used and 'user' or 'auto'
%     w, wQuantile           returned width and the raw quantile q
%     seg                     segment structure (see Pose.pose_seg_build), with
%                             segments >= w flagged as seeds. Can be passed
%                             straight to Pose.pose_fix(x, y, [], [], seg)
%     isError                per segment: inside an out-and-back excursion
%     excursions              [outJump returnJump firstFrame lastFrame duration]
%     errLen                 lengths of segments flagged as errors
%     contaminationAtW      flagged fraction among inner segments >= w
%     errSurvivingAtW      fraction of flagged segments that are >= w
%     framesKeptAtW        fraction of frames in segments >= w
%     bands                   flagged rate per log2 length band
%     curves                  the above three quantities as a function of w
%
%   Example
%     M = readmatrix('ForePawL.csv');
%     [w, info] = Pose.auto_window_width(M(:,1), M(:,2), [], 'Plot', true);
%     [xFix, yFix, mask, seg] = Pose.pose_fix(M(:,1), M(:,2), [], [], info.seg);

% ---- inputs -----------------------------------------------------------
thr = [];
if ~isempty(varargin) && (isnumeric(varargin{1}) || isempty(varargin{1}))
    thr = varargin{1};
    varargin(1) = [];
end
p = inputParser;
addParameter(p, 'CancelTol', 0.3);
addParameter(p, 'MaxJumps', 6);
addParameter(p, 'HomeRatio', 2);
addParameter(p, 'Quantile', 0.99);
addParameter(p, 'Margin', 1.5);
addParameter(p, 'MinWidth', 2);
addParameter(p, 'Plot', false);
parse(p, varargin{:});
o = p.Results;

x = x(:); y = y(:);
N = numel(x);
if numel(y) ~= N
    error('auto_window_width:size', 'x and y must have the same length.');
end
if isempty(thr)
    thr = Pose.auto_jump_threshold(x, y);
    thrSource = 'auto';
else
    thrSource = 'user';
end

% ---- 1. jumps and segments --------------------------------------------
dx = diff(x); dy = diff(y);
d  = hypot(dx, dy);
J  = find(d > thr | ~isfinite(d));     % jump between frame J(k) and J(k)+1
K  = numel(J);
V  = [dx(J) dy(J)];                    % jump vectors (NaN for missing data)
S  = [1; J + 1];                       % segment m runs S(m):E(m)
E  = [J; N];                           % segment m lies between jump m-1 and m
L  = E - S + 1;
M  = numel(L);

% ---- 2-3. out-and-back excursions --------------------------------------
isErr = false(M, 1);
exc   = zeros(0, 5);
i = 1;
while i <= K
    ni = hypot(V(i,1), V(i,2));
    C  = V(i,:);
    closed = false;
    for j = i+1 : min(K, i + o.MaxJumps - 1)
        C = C + V(j,:);
        if hypot(C(1), C(2)) < o.CancelTol * ni      % label came back
            n = J(j) - J(i);                          % frames away
            if n <= o.HomeRatio * max(L(i), L(j+1))  % home rule
                isErr(i+1:j) = true;
                exc(end+1, :) = [i, j, J(i)+1, J(j), n]; %#ok<AGROW>
                i = j + 1;
                closed = true;
            end
            break;                                    % first return only
        end
    end
    if ~closed
        i = i + 1;
    end
end

% ---- 4. width from error-segment lengths -------------------------------
errLen = L(isErr);
if isempty(errLen)
    warning('auto_window_width:noErrors', ...
        'No out-and-back excursions found; returning MinWidth.');
    q = NaN;
    w = o.MinWidth;
else
    q = quantile_simple(errLen, o.Quantile);
    w = max(o.MinWidth, ceil(o.Margin * q));
end

% ---- diagnostics -------------------------------------------------------
inner = (2:M-1)';                       % segments with a jump on both sides
[cont, surv, kept] = tail_stats(w, L, isErr, inner, N);

info = struct();
info.thr = thr;
info.thrSource = thrSource;
info.w = w;
info.wQuantile = q;
info.nJumps = K;
info.nSegments = M;
info.nErrorSegments = sum(isErr);
info.seg = Pose.pose_seg_build(x, y, thr, w);
info.isError = isErr;
info.excursions = exc;
info.excursionColumns = {'outJump', 'returnJump', 'firstFrame', ...
                          'lastFrame', 'duration'};
info.errLen = errLen;
info.contaminationAtW = cont;
info.errSurvivingAtW = surv;
info.framesKeptAtW = kept;
info.options = o;

% flagged rate per log2 length band
edges = 2.^(0:ceil(log2(max(L))) + 1);
nb = numel(edges) - 1;
bands = struct('lo', edges(1:nb)', 'hi', edges(2:nb+1)' - 1, ...
               'n', zeros(nb,1), 'nError', zeros(nb,1), 'rate', nan(nb,1));
for b = 1:nb
    m = inner(L(inner) >= edges(b) & L(inner) < edges(b+1));
    bands.n(b) = numel(m);
    bands.nError(b) = sum(isErr(m));
    if bands.n(b) > 0
        bands.rate(b) = bands.nError(b) / bands.n(b);
    end
end
info.bands = bands;

% curves over a log-spaced grid of candidate widths
wg = unique(round(logspace(0, log10(max(L)), 200)))';
cc = zeros(size(wg)); ss = cc; kk = cc;
for g = 1:numel(wg)
    [cc(g), ss(g), kk(g)] = tail_stats(wg(g), L, isErr, inner, N);
end
info.curves = struct('w', wg, 'contamination', cc, ...
                     'errSurviving', ss, 'framesKept', kk);

if o.Plot
    plot_diag(info);
end
end

% =======================================================================
function [cont, surv, kept] = tail_stats(w, L, isErr, inner, N)
tail = inner(L(inner) >= w);
if isempty(tail), cont = NaN; else, cont = mean(isErr(tail)); end
nErr = sum(isErr);
if nErr == 0, surv = 0; else, surv = sum(isErr & L >= w) / nErr; end
kept = sum(L(L >= w)) / N;
end

% =======================================================================
function q = quantile_simple(v, p)
% Nearest-rank quantile (no Statistics Toolbox needed).
v = sort(v(:));
k = min(numel(v), max(1, ceil(p * numel(v))));
q = v(k);
end

% =======================================================================
function plot_diag(info)
w = info.w;
figure('Color', 'w', 'Position', [100 100 1100 330]);

% 1. flagged rate by segment length
subplot(1, 3, 1);
b = info.bands;
ok = b.n > 0;
mid = sqrt(b.lo(ok) .* (b.hi(ok) + 1));
semilogx(mid, 100 * b.rate(ok), 'ko-', 'MarkerFaceColor', 'k');
hold on;
yl = ylim; ylim([0 max(yl(2), 5)]); yl = ylim;
plot([w w], yl, 'r-', 'LineWidth', 1.5);
xlabel('segment length (frames)');
ylabel('% flagged as error');
title('Error rate by segment length');
grid on;

% 2. error-segment length distribution
subplot(1, 3, 2);
el = info.errLen;
if ~isempty(el)
    e = 2.^(0:ceil(log2(max(el))) + 1);
    c = histcounts(el, e);
    bar(log2(e(1:end-1)), c, 1, 'FaceColor', [0.8 0.4 0.4], 'EdgeColor', 'none');
    hold on;
    yl = ylim;
    plot(log2([info.wQuantile info.wQuantile]), yl, 'k--', 'LineWidth', 1.2);
    plot(log2([w w]), yl, 'r-', 'LineWidth', 1.5);
    t = 0:2:log2(e(end));
    set(gca, 'XTick', t, 'XTickLabel', arrayfun(@(k) sprintf('%d', 2^k), t, ...
        'UniformOutput', false));
    legend({'error segments', ...
        sprintf('q%.0f = %d', 100 * info.options.Quantile, info.wQuantile), ...
        sprintf('w = %d', w)}, 'Location', 'northeast');
end
xlabel('error segment length (frames)');
ylabel('count');
title(sprintf('%d error segments', numel(el)));

% 3. what you keep vs what slips through
subplot(1, 3, 3);
cv = info.curves;
semilogx(cv.w, 100 * cv.framesKept, 'b-', 'LineWidth', 1.5);
hold on;
semilogx(cv.w, 100 * cv.contamination, 'm-', 'LineWidth', 1.5);
semilogx(cv.w, 100 * cv.errSurviving, 'Color', [0.9 0.5 0], 'LineWidth', 1.5);
yl = ylim;
plot([w w], yl, 'r-', 'LineWidth', 1.5);
xlabel('seed width w (frames)');
ylabel('%');
legend({'frames kept', 'flagged among segs \geq w', ...
        'errors surviving w', sprintf('w = %d', w)}, 'Location', 'east');
title(sprintf('w = %d: keep %.1f%% frames, %.1f%% flagged', w, ...
    100 * info.framesKeptAtW, 100 * info.contaminationAtW));
grid on;
end
