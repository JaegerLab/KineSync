function hd = set_param(hd, param)
% hd = Shared.set_param(hd, param)
% restore ui values from parameters
    fields = fieldnames(param);
    for k = 1:length(fields)
        field = fields{k};
        if isfield(hd, field) && isgraphics(hd.(field))
            values = param.(field);
            order = {'Limits','Items','ItemsData','MajorTicks','MajorTickLabels','Value','Text','Enable'};
            for j = 1:numel(order)
                prop = order{j};
                if isfield(values, prop), set(hd.(field), prop, values.(prop)); end
            end
        end
    end
end
