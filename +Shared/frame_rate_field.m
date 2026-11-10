function field = frame_rate_field(parent)
%FRAME_RATE_FIELD Edit field for the shared frame rate.
% Typing a rate overrides the automatic one. Clearing the field or typing 0
% returns to automatic: the field then shows the rate from the ephys
% synchronization, the video, or 1 (frame units), in italics. It follows
% InfoChanged itself.
data = Shared.SessionData.instance();
field = uieditfield(parent, 'numeric', 'Limits', [0 Inf], 'AllowEmpty', 'on', ...
    'ValueDisplayFormat', 'Frame rate: %.5g Hz', ...
    'ValueChangedFcn', @(src,~)data.setFrameRate(src.Value));
listener = addlistener(data, 'InfoChanged', @(~,~)showRate(field, data));
field.DeleteFcn = @(~,~)delete(listener);
showRate(field, data);
end

function showRate(field, data)
if ~isvalid(field), return; end
[rate, source] = data.getFrameRate();
field.Value = rate;
switch source
    case 'manual'
        field.FontAngle = 'normal';
        field.Tooltip = 'Typed-in rate, also used instead of the synchronized times. Clear it or enter 0 for automatic.';
        return;
    case 'sync'
        from = ['ephys synchronization (' data.ephys.sync.digitalChannelName ')'];
    case 'video'
        from = 'video file';
    otherwise
        from = 'no source: times are frame numbers';
end
field.FontAngle = 'italic';
field.Tooltip = ['Automatic, ' from '. Type a rate to override.'];
end
