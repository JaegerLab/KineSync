function channels = ttl_channels(t, digital, names)
% channels = Ephys.ttl_channels(t, digital, names)
% Rising and falling edge times of sampled digital inputs.
%   t:        sample times (n x 1)
%   digital:  n x m logical/0-1 samples, one column per channel
%   names:    cellstr of m channel names (default DIN-00, DIN-01, ...)
%   channels: 1 x m struct array: name, rise, fall (column vectors, s)
    m = size(digital, 2);
    if nargin < 3 || isempty(names)
        names = arrayfun(@(k)sprintf('DIN-%02d', k-1), 1:m, 'UniformOutput', false);
    end
    channels = struct('name', names(:)', 'rise', [], 'fall', []);
    t = t(:);
    for k = 1:m
        edges = diff(double(digital(:,k)));
        channels(k).rise = t(1 + find(edges > 0.5));
        channels(k).fall = t(1 + find(edges < -0.5));
    end
end
