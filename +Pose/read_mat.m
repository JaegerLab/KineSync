function tablePose=read_mat(filename)
% read .mat files
% Li Su, 2023/12/20

x=load(filename); %put the variable under x to avoid conflict

if isfield(x,'markerpos')
    % Aureli's data format
    bodyparts = fieldnames(x.markerpos)';
    markerNum = length(bodyparts);
    coords = fieldnames(x.markerpos.(bodyparts{1}))';
    rowNum = length(x.markerpos.(bodyparts{1}).(coords{1}));
    varnames = strcat(repelem(bodyparts,1,3), {'_'}, repmat(coords,1,markerNum));
    arrayPose = zeros(rowNum, markerNum*3);
    scorer = ''; % to do: add later if scorer is available
    for ii = 1:markerNum
        coords = fieldnames(x.markerpos.(bodyparts{ii}))';
        for jj = 1:length(coords)
            arrayPose(:,(ii-1)*3+jj)=x.markerpos.(bodyparts{ii}).(coords{jj})';
        end
    end
    tablePose = array2table(arrayPose);
    tablePose.Properties.VariableNames = varnames;
    tablePose.Properties.UserData = bodyparts;
    tablePose.Properties.Description = scorer;
else
    warndlg('File format not recognized');
    error('File format not recognized');
end



