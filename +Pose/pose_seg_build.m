function seg = pose_seg_build(x, y, jumpThresh, seedWidth, extraBreaks)
%POSE_SEG_BUILD  Split a pose trajectory into segments at jumps.
%
%   seg = Pose.pose_seg_build(x, y, jumpThresh)
%   seg = Pose.pose_seg_build(x, y, jumpThresh, seedWidth)
%   seg = Pose.pose_seg_build(x, y, jumpThresh, seedWidth, extraBreaks)
%
%   A jump is a frame-to-frame displacement > jumpThresh, or a NaN
%   displacement. Segment m runs from seg.start(m) to seg.stop(m); jump k
%   lies between segment k and k+1, i.e. after frame seg.stop(k).
%   If seedWidth is given, segments with len >= seedWidth are flagged as
%   seeds. extraBreaks (frame indices t) adds boundaries after frame t,
%   e.g. where a mask changes value.
%
%   Segment structure (shared by pose_fix and auto_window_width)
%   Per segment (M x 1):
%     start, stop, len   first frame, last frame, number of frames
%     flag               2  seed (>= seedWidth, or confirmed by the user)
%                        1  good, recovered by propagation
%                        0  not flagged yet
%                       -1  bad (jumped away from a good neighbour)
%                       -2  questionable (checked, did not match)
%                       -3  rejected by the user (locked bad)
%                        good frames: flag > 0
%     isNew             true = edited, recheck around it (see pose_fix)
%     round              propagation round in which the flag was set
%                        (0 for seeds/locked, NaN if never flagged)
%     err                distance to the interpolation when last checked
%   Per jump ((M-1) x 1):
%     conflict           both neighbouring segments are good
%     suggestion         '', 'merge', 'split' or 'review' (conflicts only)
%     suggestAt         frame t to pass to pose_seg_toggle_jump (NaN if none)
%   Scalars:
%     nFrames, jumpThresh, seedWidth (NaN if unknown)

if nargin < 4 || isempty(seedWidth), seedWidth = NaN; end
if nargin < 5, extraBreaks = []; end

x = x(:); y = y(:);
N = numel(x);
d = hypot(diff(x), diff(y));
J = find(d > jumpThresh | ~isfinite(d));
J = unique([J; extraBreaks(:)]);
J = J(J >= 1 & J < N);

S = [1; J + 1];
E = [J; N];
M = numel(S);

seg = struct();
seg.start      = S;
seg.stop       = E;
seg.len        = E - S + 1;
seg.flag       = zeros(M, 1);
seg.isNew     = false(M, 1);
seg.round      = nan(M, 1);
seg.err        = nan(M, 1);
seg.conflict   = false(M - 1, 1);
seg.suggestion = repmat({''}, M - 1, 1);
seg.suggestAt = nan(M - 1, 1);
seg.nFrames    = N;
seg.jumpThresh = jumpThresh;
seg.seedWidth   = seedWidth;

if ~isnan(seedWidth)
    isSeed = seg.len >= seedWidth;
    seg.flag(isSeed)  = 2;
    seg.round(isSeed) = 0;
end
end
