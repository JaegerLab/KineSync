function param = get_param(hd)
% param = Shared.get_param(hd)
% change ui handles to parameters
    fields = fieldnames(hd);
    param = struct();
    props = {'Value', 'Text', ...
        'Limits', 'MajorTicks', 'MajorTickLabels', ...
        'Items', 'ItemsData', ...
        'Enable'};
    for k = 1:length(fields)
        field = fields{k};
        if isgraphics(hd.(field))
            % get fields that are settable and in the props
            settableProps = fieldnames(set(hd.(field)));
            fieldsToKeep = intersect(settableProps, props);
            propCell = get(hd.(field), fieldsToKeep);
            param.(field) = cell2struct(propCell', fieldsToKeep);
        end
    end
end
