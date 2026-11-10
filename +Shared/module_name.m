function name = module_name(module)
% name = Shared.module_name(module)
% Display name of a module: 'video' -> 'Video', 'ephys' -> 'Ephys',
% 'pose' -> 'Pose', 'behav' -> 'Behavior'.

    names = struct('video', 'Video', 'ephys', 'Ephys', 'pose', 'Pose', 'behav', 'Behavior');
    name = names.(module);
end
