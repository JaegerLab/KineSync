function [xFix, yFix, p, present] = apply_point_edits(x, y, mask, seg, edit)
%APPLY_POINT_EDITS  Fixed trace from good frames and user point edits.
%
%   [xFix, yFix, p, present] = Pose.apply_point_edits(x, y, mask, seg, edit)
%
%   A frame is missing if it has no point (raw NaN and none added) or the
%   user removed it. Missing frames stay NaN and are never interpolated.
%   Every run of present frames (e.g. one lick) is interpolated on its own
%   (pchip) through its anchors: good frames (mask) and added points.
%   Before the first / after the last anchor of a run the nearest anchor is
%   held. A run with no anchor keeps its raw values, for review.
%
%   Inputs
%     x, y     raw coordinates of one body part
%     mask     good frames (Pose.pose_seg_mask)
%     seg      segment structure, for the likelihood ([] -> NaN likelihood)
%     edit     point edit record (Pose.point_edit), or [] for none
%   Outputs
%     xFix, yFix  fixed trace, NaN at missing frames
%     p           likelihood: Pose.seg_likelihood, 1 at added points,
%                 NaN at missing frames
%     present     logical, frames with a point
%
%   See also Pose.point_edit, Pose.pose_fix, Pose.refresh_preview.

x = x(:); y = y(:);
N = numel(x);
mask = logical(mask(:));
edit = Pose.point_edit(edit, N);

added = isfinite(edit.addX) & isfinite(edit.addY);
xe = x; ye = y;
xe(added) = edit.addX(added);
ye(added) = edit.addY(added);
present = isfinite(xe) & isfinite(ye) & ~edit.removed;
anchor = present & (mask | added);

xFix = nan(N, 1); yFix = xFix;
d = diff([false; present; false]);
rs = find(d == 1); re = find(d == -1) - 1;
for i = 1:numel(rs)
    fr = (rs(i):re(i))';
    g = anchor(fr);
    if any(g)
        [xFix(fr), yFix(fr)] = interp_hold(fr, xe, ye, g);
    else
        xFix(fr) = xe(fr); yFix(fr) = ye(fr);
    end
end

if nargout > 2
    if isempty(seg), p = nan(N, 1); else, p = Pose.seg_likelihood(seg); end
    p = p(:);
    p(added) = 1;
    p(~present) = NaN;
end
end

function [xr, yr] = interp_hold(fr, x, y, g)
% pchip through anchors fr(g); hold the nearest anchor outside them.
gi = fr(g);
if numel(gi) == 1
    xr = repmat(x(gi), size(fr)); yr = repmat(y(gi), size(fr));
    return;
end
xr = interp1(gi, x(gi), fr, 'pchip', NaN);
yr = interp1(gi, y(gi), fr, 'pchip', NaN);
lo = fr < gi(1);   xr(lo) = x(gi(1));   yr(lo) = y(gi(1));
hi = fr > gi(end); xr(hi) = x(gi(end)); yr(hi) = y(gi(end));
end
