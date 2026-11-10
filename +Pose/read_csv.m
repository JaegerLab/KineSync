function tablePose = read_csv (filename)
% read csv format created by DeepLabCut
% Li Su, 2023/12/18
% The zero-based index column is kept as 1-based frame numbers in
% tablePose.Properties.CustomProperties.FrameIndex; a file cropped by
% KineSync starts after frame 1 (see Pose.align_frames).
% Multi-animal files (an 'individuals' header row, e.g. maDLC or SLEAP's
% DLC export) name each body part <animal>_<bodypart>.

opts = delimitedTextImportOptions;
opts.DataLines = [1 4];
txt = readmatrix(filename,opts);
if isequal(txt{2,1},'individuals')
    nHeader = 4;
    bodyparts = strcat(txt(2,:), {'_'}, txt(3,:));
else
    nHeader = 3;
    txt(4:end,:) = [];
    bodyparts = txt(2,:);
end
coords = txt(nHeader,:);
headers = genvarname(strcat(bodyparts, {'_'}, coords));

% read data; a file with headers only gives an empty table
tablePose=readtable(filename, 'NumHeaderLines',nHeader, 'ReadVariableNames',false);
if width(tablePose) ~= numel(headers)
    tablePose = array2table(zeros(0, numel(headers)));
end

% the first column holds frame indices if its header is 'coords'
frames = (1:height(tablePose))';
if isequal(coords{1},'coords')
    frames = tablePose{:,1} + 1;
    tablePose(:,1)=[];
    headers(1)=[];
    bodyparts(1)=[];
    txt(:,1)=[];
end

tablePose.Properties.VariableNames = headers;
tablePose.Properties.UserData = unique(bodyparts,'stable');
tablePose.Properties.Description = filename; %source filename
tablePose = addprop(tablePose,{'Scorer','FrameIndex'},{'table','table'});
tablePose.Properties.CustomProperties.Scorer = txt{1,1};
tablePose.Properties.CustomProperties.FrameIndex = frames;
