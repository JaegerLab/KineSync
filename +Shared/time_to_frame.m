function frame = time_to_frame(frameTimes, t)
%TIME_TO_FRAME Nearest matched frame, clamped to the measured time range.
indices = find(isfinite(frameTimes));
if isempty(indices), error('KineSync:timing:noFrames', 'No aligned frames are available.'); end
if numel(indices) == 1
    frame = repmat(indices,size(t));
else
    frame = interp1(frameTimes(indices), double(indices), t, 'nearest', 'extrap');
end
end
