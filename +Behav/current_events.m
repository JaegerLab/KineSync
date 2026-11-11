function s = current_events(data)
%CURRENT_EVENTS Events to display in other viewers, or [] when there are none.
%   s = Behav.current_events(data) returns a struct with fields
%       t    event times (s), row-aligned with idx
%       idx  frame indices of the selected event type
%       x, y body-part position at each event, in pixels
%   for the body part, trace and event type selected in the Behavior viewer.
%   Returns [] when events are not current for that selection or the
%   "Events" checkbox is off. Viewers draw their own markers from this.
s = [];
if ~Behav.events_current(data), return; end
sel = data.behav.selection;
if ~sel.show, return; end
bodypart = data.behav.bodypart(sel.bodypart);
if ~isfield(bodypart, sel.event), return; end
idx = bodypart.(sel.event);
idx = idx(:);
s.idx = idx;
s.t = data.behav.t(idx);
s.t = s.t(:);
s.x = bodypart.rawX(idx);
s.y = bodypart.rawY(idx);
s.x = s.x(:);
s.y = s.y(:);
end
