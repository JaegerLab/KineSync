function data = scale_binary_channels(raw, channels, targetUnit)
%SCALE_BINARY_CHANNELS Apply per-channel Open Ephys bit_volts and physical units.
% raw is samples-by-channels; metadata must correspond to those channels.
if size(raw,2) ~= numel(channels)
    error('ephys:units:channels','Scaling metadata does not match sample channels.');
end
data = double(raw);
for k = 1:numel(channels)
    ch = channels(k);
    if ~isfield(ch,'bit_volts') || ~isfield(ch,'units')
        error('ephys:units:metadata','Open Ephys channel is missing bit_volts or units metadata.');
    end
    validateattributes(ch.bit_volts, {'numeric'}, {'scalar','finite','positive'});
    sourceScale = unit_scale(ch.units);
    targetScale = unit_scale(targetUnit);
    data(:,k) = data(:,k) * ch.bit_volts * sourceScale/targetScale;
end
end

function scale = unit_scale(unit)
unit = lower(strtrim(char(unit)));
unit = strrep(strrep(unit,'µ','u'),'μ','u');
switch unit
    case {'v','volt','volts'}, scale = 1;
    case {'mv','millivolt','millivolts'}, scale = 1e-3;
    case {'uv','microvolt','microvolts'}, scale = 1e-6;
    case {'nv','nanovolt','nanovolts'}, scale = 1e-9;
    otherwise, error('ephys:units:unknown','Unsupported Open Ephys voltage unit: %s',unit);
end
end
