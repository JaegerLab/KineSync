function data = ephys_read(folder)
% Syntax:
%  data = Ephys.ephys_read(filename);
%

if nargin==0
    folder = uigetdir('*.*', 'Select directory containing ephys data');
    if isequal(folder, 0), return; end
end

files = dir(folder); % structure of files
files = files(~[files.isdir]);
entries = dir(folder);

if any(contains({files.name},'.rh'))
    % Intan
    data = Ephys.read_intan(files);
elseif any(contains({entries.name},'Record Node'))
    % Open Ephys
    % go to https://github.com/open-ephys/open-ephys-matlab-tools
    % for documentations 
    data = Ephys.read_ephys(folder);
else
    error('Ephys data not found in selected folder');
end
