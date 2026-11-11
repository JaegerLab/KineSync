function edit = point_edit(edit, N, frame, action, xy)
%POINT_EDIT  Record user point edits on the Pose Fix preview.
%
%   edit = Pose.point_edit([], N)                       empty record, N frames
%   edit = Pose.point_edit(edit, N, f, 'add', [x y])    set the point at frame f
%   edit = Pose.point_edit(edit, N, f, 'remove')        mark frame f missing
%
%   The record lives with the preview (data.pose.pointEdit), so re-running
%   Pose.pose_fix after a segment edit keeps the point edits.
%     addX, addY  N x 1, the user's point (NaN = no point added)
%     removed     N x 1 logical, the user marked the frame missing
%   Adding and removing at the same frame replace each other.
%
%   See also Pose.apply_point_edits, Pose.refresh_preview.

if isempty(edit)
    edit = struct('addX', nan(N, 1), 'addY', nan(N, 1), 'removed', false(N, 1));
elseif numel(edit.removed) ~= N
    error('pose:point_edit:size', ...
        'The point edit record has %d frames, the trace %d.', numel(edit.removed), N);
end
if nargin < 3, return; end

if ~isscalar(frame) || frame < 1 || frame > N || frame ~= round(frame)
    error('pose:point_edit:frame', 'Frame must be an integer in 1..%d.', N);
end
switch action
    case 'add'
        if numel(xy) ~= 2 || ~all(isfinite(xy))
            error('pose:point_edit:xy', 'A point needs finite [x y].');
        end
        edit.addX(frame) = xy(1);
        edit.addY(frame) = xy(2);
        edit.removed(frame) = false;
    case 'remove'
        edit.addX(frame) = NaN;
        edit.addY(frame) = NaN;
        edit.removed(frame) = true;
    otherwise
        error('pose:point_edit:action', 'Action must be ''add'' or ''remove''.');
end
end
