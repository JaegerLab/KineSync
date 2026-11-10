function seg = pose_seg_toggle_jump(seg, t)
%POSE_SEG_TOGGLE_JUMP  Add or remove the jump between frame t and t+1.
%
%   seg = Pose.pose_seg_toggle_jump(seg, t)
%
%   If there is a jump after frame t, it is removed and the two segments
%   are merged. Otherwise the segment containing frames t and t+1 is split
%   there. The resulting segment(s) get flag 0 and isNew = true, so the
%   next call to pose_fix(x, y, [], [], seg) re-judges them by the
%   normal rules (seed if len >= seedWidth, otherwise propagation) and
%   rechecks only the stretch between the nearest original seeds.
%
%   Only the standard fields (see pose_seg_build) are kept in sync.

N = seg.nFrames;
if ~isscalar(t) || t ~= round(t) || t < 1 || t >= N
    error('pose_seg_toggle_jump:range', 't must be an integer in 1..%d.', N - 1);
end
M = numel(seg.start);
k = find(seg.stop == t, 1);

if ~isempty(k) && k < M
    % ---- remove jump k: merge segment k and k+1 ------------------------
    seg.stop(k) = seg.stop(k + 1);
    seg.len(k)  = seg.stop(k) - seg.start(k) + 1;
    seg = reset_segments(seg, k);
    seg = remove_rows(seg, k + 1, k);
else
    % ---- add a jump after frame t: split the segment containing t ------
    k = find(seg.start <= t & seg.stop > t, 1);
    oldStop = seg.stop(k);
    seg = insert_rows(seg, k);              % duplicate row k as k+1
    seg.stop(k)      = t;
    seg.len(k)       = t - seg.start(k) + 1;
    seg.start(k + 1) = t + 1;
    seg.stop(k + 1)  = oldStop;
    seg.len(k + 1)   = oldStop - t;
    seg = reset_segments(seg, [k, k + 1]);
end
end

% =======================================================================
function seg = reset_segments(seg, k)
seg.flag(k)   = 0;
seg.isNew(k) = true;
seg.round(k)  = NaN;
seg.err(k)    = NaN;
end

function seg = remove_rows(seg, segRow, jumpRow)
for f = {'start', 'stop', 'len', 'flag', 'isNew', 'round', 'err'}
    seg.(f{1})(segRow) = [];
end
for f = {'conflict', 'suggestion', 'suggestAt'}
    seg.(f{1})(jumpRow) = [];
end
end

function seg = insert_rows(seg, k)
% New segment k+1 (copy of k) and new jump k (between new k and k+1).
for f = {'start', 'stop', 'len', 'flag', 'isNew', 'round', 'err'}
    v = seg.(f{1});
    seg.(f{1}) = [v(1:k); v(k); v(k+1:end)];
end
seg.conflict   = [seg.conflict(1:k-1);   false; seg.conflict(k:end)];
seg.suggestion = [seg.suggestion(1:k-1); {''};  seg.suggestion(k:end)];
seg.suggestAt = [seg.suggestAt(1:k-1); NaN;   seg.suggestAt(k:end)];
end
