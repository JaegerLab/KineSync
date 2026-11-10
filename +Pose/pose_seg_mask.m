function mask = pose_seg_mask(seg)
%POSE_SEG_MASK  Frame-level good mask from a segment structure (flag > 0).
%
%   mask = Pose.pose_seg_mask(seg)   returns an nFrames x 1 logical vector.

mask = repelem(seg.flag(:) > 0, seg.len(:));
end
