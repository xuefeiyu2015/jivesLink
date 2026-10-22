% jivesBROnline.m
% Online psychometric function plot for Jives free-choice task via Blackrock.
%
% Architecture:
%   T1 (250 ms) — getJivesData.m    reads cbmex buffers, parses Jives comments
%   T2 (1 s)    — jivesAnalysisSwitchyard.m   dispatches to task-specific plot
%
% Usage:
%   1. Run this script.
%   2. Run cleanup script
%% Set up paths
%{
mbMEX_path = 'C:\Program Files\Blackrock Microsystems\Cerebus Central Suite';
addpath(mbMEX_path);
%}
%{
mbMEX_path = 'C:\Program Files\Blackrock Microsystems\Cerebus Central Suite';
if ~contains(path, mbMEX_path)
    addpath(mbMEX_path);
    savepath;
end
jivesBROnline_path = 'D:\jivesLink';
if ~contains(path, jivesBROnline_path)
    addpath(genpath(jivesBROnline_path));
    savepath;
end
%}
%% Cleanup any previous session
if exist('T1','var') && isvalid(T1), stop(T1); delete(T1); end
if exist('T2','var') && isvalid(T2), stop(T2); delete(T2); end
cbmex('close')
try
    global fhComments fhTrials fhSpikes;
    if ~isempty(fhComments) && fhComments > 0; fclose(fhComments); end
    if ~isempty(fhTrials)   && fhTrials   > 0; fclose(fhTrials);   end
    if ~isempty(fhSpikes)   && fhSpikes   > 0; fclose(fhSpikes);   end
catch; end
clear global
close all;


dbstop if error

%% Connect
% Opens cbmex and pings the NSP; 50 = comment buffer size.
try
    cbmexConnect(50);
catch ME
    errordlg(ME.message, 'Central not ready', 'modal');
    return
end

%% Timers
%% Global state
global inTrial;
inTrial = false;

global trials;
trials =struct([]);

% Companions to `trials`, appended in lockstep by getJivesData:
%   spikeTrials  per-trial flat spike arrays (.ts/.ch/.unit)
%   tsum         preallocated numeric mirror read by the dashboard/psychometrics
%   spikeNCh/spikeNUnits  spike-buffer dimensions; size the RF dropdowns
global spikeTrials tsum spikeNCh spikeNUnits;
spikeTrials = [];
tsum        = [];
spikeNCh    = [];
spikeNUnits = [];

global fhComments fhTrials fhSpikes;
dtStr       = datestr(now, 'yyyymmdd_HHMMSS');
commentFile = ['comments_' dtStr '.txt'];
trialFile   = ['trials_'   dtStr '.csv'];
spikeFile   = ['spikes_ch1_' dtStr '.txt'];
fhComments  = fopen(commentFile, 'w');
fhTrials    = fopen(trialFile,   'w');
fhSpikes    = fopen(spikeFile,   'w');   % channel-1 unit-1/unit-2 spike timings
% 18 columns — must match the fprintf in getJivesData exactly.
fprintf(fhTrials, 'Trial_number,Task,Trial_type,Start,End,Trialoutcome,Choiceoutcome,Choosen_choice,Choicetime,Target_1_presented,Target_2_presented,Target_1_pos_x,Target_1_pos_y,Target_2_pos_x,Target_2_pos_y,Requested_target_2_time_offset,Fixation_exited,Fixation_point_off\n');
fprintf('[Export] comments → %s\n', fullfile(pwd, commentFile));
fprintf('[Export] trials   → %s\n', fullfile(pwd, trialFile));
fprintf('[Export] spikes   → %s\n', fullfile(pwd, spikeFile));

% REVISED: removed base-workspace `data` variable — getJivesData now
% appends directly to global `trials`; jivesAnalysisSwitchyard reads it.
T1 = timer('Name',          'Jives_Acquire', ...
           'Period',         0.25, ...
           'ExecutionMode', 'fixedSpacing', ...
           'TimerFcn',       'getJivesData();', ...           % REVISED
           'ErrorFcn',       @(~,e) errordlg(sprintf(['Acquisition stopped:\n%s\n\n' ...
               'If Central was closed or the NSP disconnected, reopen Central ' ...
               'and rerun jivesBROnline.'], e.Data.message), 'Acquisition error'));

T2 = timer('Name',          'Jives_Plot', ...
           'Period',         1.0, ...
           'ExecutionMode', 'fixedSpacing', ...
           'TimerFcn',       'jivesAnalysisSwitchyard();', ... % REVISED
           'ErrorFcn',       @(~,e) fprintf('[T2 error] %s\n', e.Data.message));

fprintf('Online acquisition running.');
start(T1);
start(T2);
%fprintf('Online acquisition running. Run cleanup block to stop.\n');

%% Cleanup  (run when done)
%{
 stop(T1); delete(T1);
 stop(T2); delete(T2);
 cbmex('trialconfig', 0);
 cbmex('close');
 global fhComments fhTrials fhSpikes;
 if ~isempty(fhComments) && fhComments > 0; fclose(fhComments); fhComments = []; end
 if ~isempty(fhTrials)   && fhTrials   > 0; fclose(fhTrials);   fhTrials   = []; end
 if ~isempty(fhSpikes)   && fhSpikes   > 0; fclose(fhSpikes);   fhSpikes   = []; end
%}