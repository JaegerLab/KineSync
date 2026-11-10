function tablePose = read_h5(filename)
% read deeplabcut h5 files into a table. with proper variable names
% syntax: marker = read_h5(filename)
% ------------------------
% Li Su, 2023/12/18

% read data
data = h5read(filename,'/df_with_missing/table');
tablePose=array2table(data.values_block_0');

% read headers in meta info.
[bodyparts, scorer ,coords] = Pose.read_h5_bodyparts(filename);
% replace illegal characters
bodyparts=strrep(bodyparts,'-','_');
% repeat each bodyparts 3 times, add suffix _x,y,likelihood to the end.
headers=genvarname(strcat(repelem(bodyparts,1,length(coords)), ...
                          {'_'}, ...
                          repmat(coords,1,length(bodyparts))));
% define them as variable names in the table.
tablePose.Properties.VariableNames = headers;

% store scorer
tablePose.Properties.Description = filename;
tablePose = addprop(tablePose,'Scorer','table');
tablePose.Properties.CustomProperties.Scorer = scorer;
% store bodyparts
tablePose.Properties.UserData = bodyparts;


