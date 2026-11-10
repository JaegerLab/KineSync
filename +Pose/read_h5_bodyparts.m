function [bodyparts, scorer, coords]=read_h5_bodyparts(filename)
% extract the bodyparts labels from a DeepLabCut h5 file
% syntax: 
%    bodyparts = read_h5_bodyparts(filename)
%    [bodyparts, scorer, coords] = read_h5_bodyparts(filename)
% INPUT arguments:
%   filename: a string
% OUTPUT arguments:
%   bodyparts: a cell array of strings
%   scorer: optional, a string, the name of the DLC model used.
%   coords: optional, always returns {'x','y','likelihood'}
% -----------------------------
% Li Su, 2023-12-18

% get the header string
attribute = h5readatt(filename,'/df_with_missing','non_index_axes');

% parse the string===============
% Get the strings between 'V' and '\n'
parsedStrings = regexp(attribute, '(?<=V)[^\n]+(?=\n)', 'match'); 

bodyparts = parsedStrings([2 6:end]);
scorer = parsedStrings{1};
coords = parsedStrings(3:5);

