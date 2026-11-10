function data=read_intan(files)
% data = read_intan(filenames)
%
% wrapper function to read_Intan_RHD2000 and read_Intan_RHS2000
% Read multiple files and concatenate data.
%
% files: a cell array of full filenames
% data: a structure with the following fields concatenated: 
%       analogData, digInData, t

if nargin==0
    [files, path] = uigetfile('*.*', 'Select Ephys File(s)', 'MultiSelect', 'on');
    if isequal(files, 0), return; end
    files = fullfile(path, files);
end

if ischar(files), files = {files}; end  % ensure cell
if isstruct(files)
    files = arrayfun(@(x)fullfile(x.folder,x.name), files, 'UniformOutput', false);
end
supported = cellfun(@(f)endsWith(lower(f), {'.rhd','.rhs'}), files, 'UniformOutput', false);
files = files(cellfun(@any, supported));
fileNum = length(files);
if fileNum == 0, error('ephys:files', 'No RHD or RHS files were selected.'); end

p = 0; % pointer for the end of data in pre-allocated space.
hd = waitbar(0, 'Please wait...', 'Name', 'Reading files');
cleanup = onCleanup(@()delete(hd)); %#ok<NASGU>
ht = findall(hd,'Type','text');
set(ht,'Interpreter','none');

for ii=1:fileNum
    fullname = files{ii};

    % disp(filename)
    [~, filename, ext] = fileparts(fullname);
    ext = lower(ext);

    if ~exist(fullname,"file"), error('File not found'); end
    
    % auto select the corresponding reader for rhd and rhs.
    if isequal(ext,'.rhd')
        waitbar(ii/fileNum, hd, sprintf('Reading: %s%s (%d/%d)', filename,ext, ii, fileNum));
        data1= Ephys.read_Intan_RHD2000(fullname,1);
    elseif isequal(ext,'.rhs')
        waitbar(ii/fileNum, hd, sprintf('Reading: %s%s (%d/%d)', filename,ext, ii, fileNum));
        data1= Ephys.read_Intan_RHS2000(fullname,1);
    else
        waitbar(ii/fileNum, hd, sprintf('Skipping: %s%s (%d/%d)', filename,ext, ii, fileNum));
        continue
    end
    
    if ~isfield(data1, 'analogData') || size(data1.analogData,1) ~= numel(data1.t)
        error('ephys:channels', 'File has no amplifier data or incompatible timestamps: %s', fullname);
    end
    if p > 0
        if data1.sampleRate ~= data.sampleRate || ...
                ~isequal({data1.analogChannels.custom_channel_name}, data.analogChannels)
            error('ephys:schema', 'Sample rate or amplifier channels changed between files.');
        end
        for field = {'digitalData','digInData'}
            name = field{1};
            if isfield(data, name) ~= isfield(data1, name) || ...
                    (isfield(data1, name) && size(data.(name),2) ~= size(data1.(name),2))
                error('ephys:schema', 'Input channel layout changed between files: %s', name);
            end
        end
    end
    if p==0
        % 1st file
        % pre-allocate space to speed up reading
        data=data1;
        len = length(data1.t);
        allLen = len * fileNum;
        % pre-allocated zeros (longer than needed).
        data.t = zeros(allLen, 1);
        data.t(1:len) = data1.t;
        if isfield(data1, 'analogData')
            data.analogData = zeros(allLen, size(data1.analogData, 2));
            data.analogData(1:len, :) = data1.analogData;
            % only keep channel names as a cell array of chars
            data.analogChannels = {data1.analogChannels.custom_channel_name};
        end
        if isfield(data1, 'digitalData')
            data.digitalData = zeros(allLen, size(data1.digitalData, 2));
            data.digitalData(1:len, :) = data1.digitalData;
        end
        if isfield(data1, 'digInData')
            data.digInData = zeros(allLen, size(data1.digInData, 2));
            data.digInData(1:len, :) = data1.digInData;
        end
        p = len;
    else
        % the rest of the files
        if abs(data1.t(1)-data.t(p)) > 1.1/data.sampleRate
            warning('Time not continuous');
        end
        len = length(data1.t);
        data.t(p+(1:len)) = data1.t;
        if isfield(data1, 'analogData')
            data.analogData(p+(1:len), :) = data1.analogData;
        end
        if isfield(data1, 'digitalData')
            data.digitalData(p+(1:len),:) = data1.digitalData;
        end
        if isfield(data1, 'digInData')
            data.digInData(p+(1:len), :) = data1.digInData;
        end
        p = p + len;
    end
end
if p < allLen
    % after reading, truncate un-used trailing zeros.
    data.t(p+1:allLen) = [];
    if isfield(data1, 'analogData')
        data.analogData(p+1:allLen, :) = [];
    end
    if isfield(data1, 'digitalData')
        data.digitalData(p+1:allLen, :) = [];
    end
    if isfield(data1, 'digInData')
        data.digInData(p+1:allLen, :) = [];
    end
end
data.files = files;
close(hd)