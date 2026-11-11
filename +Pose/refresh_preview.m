function refresh_preview(data)
%REFRESH_PREVIEW  Rebuild the Pose Fix preview columns from the segments and point edits.
%
%   Pose.refresh_preview(data)
%
%   Writes temp_x, temp_y and temp_likelihood of data.pose.table from
%   data.pose.seg (its good frames) and data.pose.pointEdit, for the body
%   part data.pose.segBodypart. Callers notify PoseChanged themselves.
%
%   See also Pose.apply_point_edits, Pose.point_edit.

bodypart = data.pose.segBodypart;
x = data.pose.table.([bodypart '_x']);
y = data.pose.table.([bodypart '_y']);
seg = data.pose.seg;
edit = [];
if isfield(data.pose, 'pointEdit'), edit = data.pose.pointEdit; end
edit = Pose.point_edit(edit, numel(x));
[tx, ty, p] = Pose.apply_point_edits(x, y, Pose.pose_seg_mask(seg), seg, edit);
data.pose.pointEdit = edit;
data.pose.table.temp_x = tx;
data.pose.table.temp_y = ty;
data.pose.table.temp_likelihood = p;
end
