% jivesBROnline.m
% Online psychometric function plot for Jives free-choice task via Blackrock.
%
% Architecture:
%   T1 (250 ms) — getJivesData.m    reads cbmex buffers, parses Jives comments
%   T2 (1 s)    — jivesAnalysisSwitchyard.m   dispatches to task-specific plot
%
% Usage:
%   1. Run this script.
%   2. Run cleanup block at the bottom when done.

%% Set up paths
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

%% Cleanup any previous session
if exist('T1','var') && isvalid(T1), stop(T1); delete(T1); end
if exist('T2','var') && isvalid(T2), stop(T2); delete(T2); end
cbmex('close')
clear global


dbstop if error

%% Connect
cbmex('open')
% 'comment', 200 — comment buffer size 
cbmex('trialconfig', 1, 'double', 'absolute', 'comment', 200)

%% Timers
%% Global state
global inTrial,trials;
inTrial = false;
trials = struct();
data    = [];   % base workspace: latest completed trial from T1

T1 = timer('Name',          'Jives_Acquire', ...
           'Period',         0.25, ...
           'ExecutionMode', 'fixedRate', ...
           'TimerFcn',       'tempdata = getJivesData(); if ~isempty(tempdata); data = tempdata; end', ...
           'ErrorFcn',       @(~,e) fprintf('[T1 error] %s\n', e.Data.message));

T2 = timer('Name',          'Jives_Plot', ...
           'Period',         1.0, ...
           'ExecutionMode', 'fixedRate', ...
           'TimerFcn',       'jivesAnalysisSwitchyard(data);', ...
           'ErrorFcn',       @(~,e) fprintf('[T2 error] %s\n', e.Data.message));

start(T1);
start(T2);
fprintf('Online acquisition running. Run cleanup block to stop.\n');

%% Cleanup  (run when done)
% stop(T1); delete(T1);
% stop(T2); delete(T2);
% cbmex('trialconfig', 0);
% cbmex('close');
