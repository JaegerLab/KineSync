function [xFix, yFix, mask, seg] = pose_fix(x, y, jumpThresh, seedWidth, maskOrSeg, visualize)
%POSE_FIX  Fix pose mislabels by progressive interpolation from seeds.
%
%   [xFix, yFix, mask, seg] = Pose.pose_fix(x, y)
%   [xFix, yFix, mask, seg] = Pose.pose_fix(x, y, jumpThresh, seedWidth)
%   [xFix, yFix, mask, seg] = Pose.pose_fix(x, y, jumpThresh, seedWidth, maskOrSeg)
%   [...] = Pose.pose_fix(..., visualize)
%
%   The trace is cut into segments at jumps. Segments at least seedWidth
%   long are seeds. Propagation then repeats:
%     1. undecided segments next to a good one are bad (a jump separates
%        them from a known-good position);
%     2. undecided segments next to a bad/questionable one are candidates:
%        the label may have come back. Each candidate edge that faces a
%        flagged neighbour is compared with a pchip interpolation through
%        all good frames (median over CHECK_FRAMES frames). If every
%        checked edge is within jumpThresh the candidate is good,
%        otherwise questionable. Two neighbouring candidates cannot both
%        become good in the same round: the closer match wins.
%   until no new good segments appear. Afterwards, neighbouring good
%   segments (which a jump says cannot both be right) are marked as
%   conflicts with a suggested fix.
%
%   Inputs
%     x, y         coordinates of one body part (vectors, same length)
%     jumpThresh  jump threshold. [] -> seg.jumpThresh if a segment
%                  structure is given, else Pose.auto_jump_threshold.
%     seedWidth    seed width in frames. [] -> seg.seedWidth if given,
%                  else Pose.auto_window_width (only computed if needed).
%     maskOrSeg  optional:
%                  - logical (or 0/1) vector, one value per frame: segments
%                    are cut at jumps and where the mask changes; good runs
%                    become seeds, bad runs locked bad. No propagation.
%                  - segment structure (see Pose.pose_seg_build):
%                    * segments with isNew = true were edited. A positive
%                      flag makes it a seed, a negative one locks it bad,
%                      flag 0 (new geometry after split/merge) re-judges it
%                      (seed if len >= seedWidth, else propagation). Only
%                      the stretch between the nearest original seeds on
%                      either side is rechecked.
%                    * any other flag-0 segments are propagated as usual.
%     visualize    true to plot the result (default false)
%
%   Outputs
%     xFix, yFix interpolated (pchip) through good frames, separately in
%                  each run of frames that have data; missing (NaN) frames
%                  stay NaN. Before the first / after the last good frame
%                  of a run the nearest good value is held; a run with no
%                  good frame keeps its raw values. See Pose.apply_point_edits.
%     mask         logical, true for frames in good segments (flag > 0)
%     seg          segment structure (flags, rounds, conflicts, suggestions)
%
%   Suggestions for conflicts (seg.suggestion, at jump k)
%     'split'  a hidden sub-threshold jump inside one side cancels the
%              detected jump, and the label stays put in between;
%              seg.suggestAt is the frame to split after
%     'merge'  the jump is close to the threshold and the motion carries on
%              in its direction, so it is probably real fast movement;
%              seg.suggestAt is the jump to remove
%     'review' neither; often a long stretch stuck on the wrong body part
%   Apply split/merge with Pose.pose_seg_toggle_jump(seg, seg.suggestAt(k)).
%
%   See also Pose.pose_seg_build, Pose.pose_seg_toggle_jump, Pose.pose_seg_mask,
%            Pose.auto_jump_threshold, Pose.auto_window_width.

% ---- tunable constants --------------------------------------------------
P.CHECK_FRAMES = 3;    % edge frames compared with the interpolation (median)
P.CANCEL_TOL   = 0.3;  % hidden jump: |jump + hidden step| < CANCEL_TOL*|jump|
P.HIDDEN_LAGS  = 3;    % a hidden jump may be spread over up to this many frames
P.MERGE_RATIO  = 1.5;  % 'merge' only for jumps below MERGE_RATIO*jumpThresh
P.MERGE_FRAMES = 5;    % frames of motion checked for continuing direction

SEED = 2; GOOD = 1; REJECT = -3;

% ---- inputs ---------------------------------------------------------------
x = x(:); y = y(:);
N = numel(x);
if numel(y) ~= N
    error('pose_fix:size', 'x and y must have the same length.');
end
if nargin < 3, jumpThresh = []; end
if nargin < 4, seedWidth = []; end
if nargin < 5, maskOrSeg = []; end
if nargin < 6 || isempty(visualize), visualize = false; end

if isempty(maskOrSeg)
    mode = 'full';
elseif isstruct(maskOrSeg)
    mode = 'seg';
elseif (islogical(maskOrSeg) || isnumeric(maskOrSeg)) && numel(maskOrSeg) == N
    mode = 'mask';
    m = maskOrSeg(:);
    if ~islogical(m)
        if ~all(m == 0 | m == 1)
            error('pose_fix:mask', 'A numeric mask may only contain 0 and 1.');
        end
        m = (m == 1);
    end
else
    error('pose_fix:input', ...
        'maskOrSeg must be a mask with one value per frame, or a segment structure.');
end

% ---- build / update segments ---------------------------------------------
switch mode
    case 'full'
        if isempty(jumpThresh), jumpThresh = Pose.auto_jump_threshold(x, y); end
        if isempty(seedWidth),   seedWidth = Pose.auto_window_width(x, y, jumpThresh); end
        seg = Pose.pose_seg_build(x, y, jumpThresh, seedWidth);
        seg = propagate(seg, x, y, 1, numel(seg.start), P);

    case 'mask'
        if isempty(jumpThresh), jumpThresh = Pose.auto_jump_threshold(x, y); end
        seg = Pose.pose_seg_build(x, y, jumpThresh, seedWidth, find(diff(m) ~= 0));
        good = m(seg.start);
        seg.flag(good)  = SEED;
        seg.flag(~good) = REJECT;
        seg.round(:) = 0;
        seg.err(:) = NaN;

    case 'seg'
        seg = check_seg(maskOrSeg, N);
        if ~isempty(jumpThresh), seg.jumpThresh = jumpThresh; end
        if isnan(seg.jumpThresh)
            seg.jumpThresh = Pose.auto_jump_threshold(x, y);
        end
        if ~isempty(seedWidth), seg.seedWidth = seedWidth; end
        M = numel(seg.start);
        region = false(M, 1);

        newIdx = find(seg.isNew);
        if ~isempty(newIdx)
            if any(seg.flag(newIdx) == 0) && isnan(seg.seedWidth)
                seg.seedWidth = Pose.auto_window_width(x, y, seg.jumpThresh);
            end
            % region: between nearest original (non-new) seeds
            isOrigSeed = (seg.flag == SEED) & ~seg.isNew;
            for k = newIdx'
                L = find(isOrigSeed(1:k-1), 1, 'last');
                if isempty(L), L = 0; end
                R = find(isOrigSeed(k+1:end), 1, 'first');
                if isempty(R), R = M + 1; else, R = R + k; end
                region(L+1:R-1) = true;
            end
            % apply the edits
            for k = newIdx'
                if seg.flag(k) > 0
                    seg.flag(k) = SEED;
                elseif seg.flag(k) < 0
                    seg.flag(k) = REJECT;
                elseif seg.len(k) >= seg.seedWidth
                    seg.flag(k) = SEED;
                end
                if seg.flag(k) ~= 0, seg.round(k) = 0; else, seg.round(k) = NaN; end
                seg.err(k) = NaN;
            end
            % reset everything else in the region that is not locked
            rs = region & ~seg.isNew & seg.flag ~= REJECT;
            seg.flag(rs) = 0;
            seg.round(rs) = NaN;
            seg.err(rs) = NaN;
            seg.isNew(:) = false;
            % propagate each region separately
            dr = diff([false; region; false]);
            a = find(dr == 1);
            b = find(dr == -1) - 1;
            for i = 1:numel(a)
                seg = propagate(seg, x, y, a(i), b(i), P);
            end
        end
        % undecided segments elsewhere (e.g. seeds-only input)
        if any(~region & seg.flag == 0)
            seg = propagate(seg, x, y, 1, M, P);
        end
end

% ---- conflicts and suggestions --------------------------------------------
seg = find_conflicts(seg, x, y, P);

% ---- output ----------------------------------------------------------------
mask = Pose.pose_seg_mask(seg);
if ~any(mask & isfinite(x) & isfinite(y))
    warning('pose_fix:noGood', 'No good frames; returning the raw trace.');
end
[xFix, yFix] = Pose.apply_point_edits(x, y, mask, seg, []);

if visualize
    plot_result(x, y, xFix, yFix, seg);
end
end

% ==========================================================================
function seg = propagate(seg, x, y, a, b, P)
% Progressive propagation, changing only undecided segments a..b. Segments
% outside a..b keep their flags and act as fixed neighbours.
GOOD = 1; BAD = -1; QUEST = -2;
F = seg.flag; rnd = seg.round; er = seg.err;
S = seg.start; E = seg.stop; L = seg.len;
M = numel(F);
thr = seg.jumpThresh;
K = P.CHECK_FRAMES;

inR = false(M, 1); inR(a:b) = true;
if a > 1, fa = S(a-1); else, fa = 1; end       % frames used for the
if b < M, fb = E(b+1); else, fb = numel(x); end % interpolation reference
fr = (fa:fb)';
xr = nan(size(fr)); yr = xr;

r = 0; growing = true; recheckQ = true;
while r <= M + 1                                 % hard stop, never reached
    r = r + 1;
    [lf, rf] = neighbours(F);
    if growing
        % 1. undecided next to good -> bad
        sel = inR & (F == 0 | F == QUEST) & (lf > 0 | rf > 0);
        F(sel) = BAD; rnd(sel) = r; er(sel) = NaN;
        [lf, rf] = neighbours(F);
    end
    % 2. undecided next to bad/questionable/locked -> candidates.
    %    Questionable ones are only rechecked when the reference changed.
    und = (F == 0) | (recheckQ & F == QUEST);
    cand = find(inR & und & (lf < 0 | rf < 0));
    if isempty(cand), break; end

    if growing
        g = repelem(F > 0, L);
        g = g(fr) & isfinite(x(fr)) & isfinite(y(fr));
        [xr, yr] = interp_hold(fr, x, y, g);
    end

    e = nan(numel(cand), 1);
    for i = 1:numel(cand)
        k = cand(i);
        ev = [];
        if lf(k) < 0
            idx = (S(k) : min(E(k), S(k) + K - 1))';
            ev(end+1) = median(hypot(x(idx) - xr(idx-fa+1), y(idx) - yr(idx-fa+1))); %#ok<AGROW>
        end
        if rf(k) < 0
            idx = (max(S(k), E(k) - K + 1) : E(k))';
            ev(end+1) = median(hypot(x(idx) - xr(idx-fa+1), y(idx) - yr(idx-fa+1))); %#ok<AGROW>
        end
        if any(isnan(ev)), e(i) = NaN; else, e(i) = max(ev); end
    end

    % accept closest matches first; never two neighbours in one round
    pass = e < thr;
    acc = false(M, 1);
    [~, ord] = sort(e);
    for i = ord'
        if ~pass(i), continue; end
        k = cand(i);
        if (k > 1 && acc(k-1)) || (k < M && acc(k+1)), continue; end
        acc(k) = true;
    end
    newF = QUEST * ones(numel(cand), 1);
    newF(acc(cand)) = GOOD;
    chg = F(cand) ~= newF;
    F(cand) = newF;
    rnd(cand(chg)) = r;
    er(cand) = e;

    growing = any(acc);
    recheckQ = growing;
    if ~growing && ~any(chg), break; end
end
seg.flag = F; seg.round = rnd; seg.err = er;
end

% ==========================================================================
function seg = find_conflicts(seg, x, y, P)
good = seg.flag > 0;
M = numel(good);
seg.conflict   = good(1:M-1) & good(2:M);
seg.suggestion = repmat({''}, M - 1, 1);
seg.suggestAt = nan(M - 1, 1);
for k = find(seg.conflict)'
    [seg.suggestion{k}, seg.suggestAt(k)] = suggest(seg, k, x, y, P);
end
end

function [s, at] = suggest(seg, k, x, y, P)
thr = seg.jumpThresh;
a = seg.stop(k); b = seg.start(k + 1);          % frames either side of jump
v = [x(b) - x(a), y(b) - y(a)];
nv = hypot(v(1), v(2));

% hidden jump: a 1..HIDDEN_LAGS frame displacement inside either side that
% cancels the detected jump (out-and-back with an undetected half), with
% the label staying at the wrong place between the two
best = Inf; bestAt = NaN;
sides = [seg.start(k), a; b, seg.stop(k + 1)];
for sd = 1:2
    f0 = sides(sd, 1); f1 = sides(sd, 2);
    for q = 1:P.HIDDEN_LAGS
        t = (f0 : f1 - q)';
        if isempty(t), continue; end
        c = hypot(v(1) + x(t+q) - x(t), v(2) + y(t+q) - y(t)) / nv;
        % ...and the label must stay where it went: the far side of the
        % hidden step matches the far side of the detected jump
        stay = hypot(x(t) - x(b), y(t) - y(b)) < thr & ...
               hypot(x(t+q) - x(a), y(t+q) - y(a)) < thr;
        c(~stay) = Inf;
        [cm, i] = min(c);
        if cm < best
            best = cm;
            t0 = t(i);
            st = hypot(diff(x(t0:t0+q)), diff(y(t0:t0+q)));
            [~, j] = max(st);
            bestAt = t0 + j - 1;                % split after this frame
        end
    end
end
if best < P.CANCEL_TOL
    s = 'split'; at = bestAt;
    return;
end

% false jump: near threshold, and motion continues in the jump direction
if nv < P.MERGE_RATIO * thr
    cont = false;
    mB = min(P.MERGE_FRAMES, seg.stop(k + 1) - b);
    if mB > 0
        cont = cont || same_direction(v, [x(b+mB) - x(b), y(b+mB) - y(b)]);
    end
    mA = min(P.MERGE_FRAMES, a - seg.start(k));
    if mA > 0
        cont = cont || same_direction(v, [x(a) - x(a-mA), y(a) - y(a-mA)]);
    end
    if cont
        s = 'merge'; at = a;                    % remove the jump after frame a
        return;
    end
end
s = 'review'; at = NaN;
end

function tf = same_direction(v, D)
nv = hypot(v(1), v(2)); nD = hypot(D(1), D(2));
tf = nD >= 0.25 * nv && (v * D') / (nv * nD) > 0.5;
end

% ==========================================================================
function [lf, rf] = neighbours(F)
lf = [NaN; F(1:end-1)];
rf = [F(2:end); NaN];
end

function [xr, yr] = interp_hold(fr, x, y, g)
% pchip through good frames fr(g); hold the nearest good value outside.
xr = nan(size(fr)); yr = xr;
gi = fr(g);
if isempty(gi), return; end
if numel(gi) == 1
    xr(:) = x(gi); yr(:) = y(gi);
    return;
end
xr = interp1(gi, x(gi), fr, 'pchip', NaN);
yr = interp1(gi, y(gi), fr, 'pchip', NaN);
lo = fr < gi(1);  xr(lo) = x(gi(1));   yr(lo) = y(gi(1));
hi = fr > gi(end); xr(hi) = x(gi(end)); yr(hi) = y(gi(end));
end

function seg = check_seg(seg, N)
need = {'start', 'stop', 'flag'};
for f = need
    if ~isfield(seg, f{1})
        error('pose_fix:seg', 'Segment structure needs field "%s".', f{1});
    end
end
seg.start = seg.start(:); seg.stop = seg.stop(:); seg.flag = double(seg.flag(:));
M = numel(seg.start);
if seg.start(1) ~= 1 || seg.stop(end) ~= N || ...
        any(seg.start(2:end) ~= seg.stop(1:end-1) + 1) || any(seg.stop < seg.start)
    error('pose_fix:seg', ...
        'Segments must be contiguous and cover frames 1..%d.', N);
end
seg.len = seg.stop - seg.start + 1;
defaults = {'isNew', false(M, 1); 'round', nan(M, 1); 'err', nan(M, 1); ...
            'conflict', false(M-1, 1); 'suggestion', repmat({''}, M-1, 1); ...
            'suggestAt', nan(M-1, 1)};
for i = 1:size(defaults, 1)
    if ~isfield(seg, defaults{i, 1}) || numel(seg.(defaults{i, 1})) ~= numel(defaults{i, 2})
        seg.(defaults{i, 1}) = defaults{i, 2};
    end
end
seg.isNew = logical(seg.isNew(:));
seg.nFrames = N;
if ~isfield(seg, 'jumpThresh') || isempty(seg.jumpThresh), seg.jumpThresh = NaN; end
if ~isfield(seg, 'seedWidth')   || isempty(seg.seedWidth),   seg.seedWidth = NaN;   end
end

% ==========================================================================
function plot_result(x, y, xFix, yFix, seg)
% The same layers and styles as the fix overlay in the Pose viewer
% (Shared.styles), plus the suggestion for each conflict.
S = Shared.styles();
N = numel(x); t = (1:N)';
fe = repelem(seg.flag, seg.len);            % flag per frame
good = fe > 0;
win = seg.seedWidth;
mk = {'LineStyle', 'none', 'MarkerSize', S.markSize, 'LineWidth', S.markWidth};
attn = {'LineStyle', 'none', 'Marker', S.attnMarker, 'MarkerSize', S.attnSize, ...
    'LineWidth', S.attnWidth};

figure('Color', 'w'); ax = gca; hold(ax, 'on');
axis(ax, 'ij');                             % image coordinates, as in the viewer

% interpolation where it replaces data, joined to the good frames
show = ~good;
show = show | [show(2:end); false] | [false; show(1:end-1)];
% jumps: from the last frame before each jump to the first frame after it
a = seg.stop(1:end-1); a = a(:);
% frame markers (seeds from the algorithm are not marked)
userGood = repelem(seg.flag == 2 & ~(seg.len >= win), seg.len);
layers = { ...
    'good',     fe == 1,  S.goodMarker,     S.good, 'none'; ...
    'userGood', userGood, S.userGoodMarker, S.good, S.good; ...
    'bad',      fe == -1, S.badMarker,      S.bad,  'none'; ...
    'quest',    fe == -2, S.questMarker,    S.grey, 'none'; ...
    'userBad',  fe == -3, S.userBadMarker,  S.bad,  'none'; ...
    'unflag',   fe == 0,  S.unflagMarker,   S.grey, 'none'};
% needs attention: frames at both ends
c = seg.stop([seg.conflict(:); false]);
k = find((seg.flag == -1 | seg.flag == -2) & seg.len >= S.longBadFrac * win);
d = diff([false; ~good & isfinite(xFix); false]);   % missing frames are not interpolated
rs = find(d == 1); re = find(d == -1) - 1;
long = (re - rs + 1) >= S.longInterpFrac * win;
attnLayers = { ...
    'attnConflict', [c; c + 1],                  S.attnConflict, false; ...
    'attnLongBad',  [seg.start(k); seg.stop(k)], S.attnLongBad,  false; ...
    'attnInterp',   [rs(long); re(long)],        S.attnInterp,   true};

% one legend entry per layer, from whichever coordinate draws it first
h = gobjects(0);
named = {};
coords = {x(:), xFix(:), S.xColor, 'x'; y(:), yFix(:), S.yColor, 'y'};
for i = 1:2
    v = coords{i, 1}; vfix = coords{i, 2};
    add(plot(ax, t, v, '-', 'Color', coords{i, 3}, 'LineWidth', S.trace), ...
        coords{i, 4}, true);
    Y = vfix; Y(~show) = NaN;
    add(plot(ax, t, Y, S.interpStyle, 'Color', S.interpColor, 'LineWidth', S.interpWidth), ...
        'interp', any(~good));
    X = [t(a) t(a+1) nan(numel(a), 1)]'; Y = [v(a) v(a+1) nan(numel(a), 1)]';
    add(plot(ax, X(:), Y(:), S.jumpStyle, 'Color', S.jumpColor, 'LineWidth', S.jumpWidth), ...
        'jump', ~isempty(a));
    for j = 1:size(layers, 1)
        sel = layers{j, 2};
        add(plot(ax, t(sel), v(sel), layers{j, 3}, 'Color', layers{j, 4}, ...
            'MarkerFaceColor', layers{j, 5}, mk{:}), layers{j, 1}, any(sel));
    end
    for j = 1:size(attnLayers, 1)
        f = attnLayers{j, 2};
        w = v; if attnLayers{j, 4}, w = vfix; end   % long interpolation: on the fix
        add(plot(ax, t(f), w(f), 'Color', attnLayers{j, 3}, attn{:}), attnLayers{j, 1}, ~isempty(f));
    end
end

% suggested fix for each conflict, at the jump
yl = ylim(ax);
for k = find(seg.conflict)'
    tc = seg.stop(k) + 0.5;
    plot(ax, [tc tc], yl, ':', 'Color', S.attnConflict, 'LineWidth', 1, ...
        'HandleVisibility', 'off');
    text(ax, tc, yl(1), [' ' seg.suggestion{k}], 'Color', S.attnConflict, ...
        'VerticalAlignment', 'top', 'Rotation', -90);
end
ylim(ax, yl);

% legend in the viewer's order
[~, idx] = ismember([{'x', 'y'}, S.legendOrder], named);
idx = idx(idx > 0);
legend(ax, h(idx), 'Location', S.legendLocation, 'AutoUpdate', 'off');
xlabel(ax, 'Frame'); ylabel(ax, 'Coordinate (pixel)');
title(ax, sprintf('%d segments, %d good (%d seeds), %d conflicts', numel(seg.flag), ...
    sum(seg.flag > 0), sum(seg.flag == 2), sum(seg.conflict)));

    % keep the first handle of each layer that has data, for the legend
    function add(hl, name, hasData)
        if isempty(hl), return; end         % plot() of no points returns no line
        hl.DisplayName = S.legend.(name);
        if hasData && ~ismember(name, named)
            h(end+1) = hl;
            named{end+1} = name;
        else
            hl.HandleVisibility = 'off';
        end
    end
end
