function t = frame_time(data, t)
%FRAME_TIME  Time of the frame the video shows at time t.
%
%   t = Shared.frame_time(data, t)
%
%   Time lines and time fields point at the frame the video shows, so they
%   snap to the nearest frame time. The frame times come from the first
%   module that has them: video, pose, behavior. Without any, t is returned
%   unchanged.

for module = {'video', 'pose', 'behav'}
    m = module{1};
    if ~data.has(m) || ~isfield(data.(m), 't') || ~any(isfinite(data.(m).t)), continue; end
    frameTimes = data.(m).t;
    t = frameTimes(Shared.time_to_frame(frameTimes, t));
    return;
end
end
