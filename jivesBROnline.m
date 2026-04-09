% jivesBROnline.m
% Online psychometric function plot for Jives free-choice task via Blackrock.
%
% Architecture:
%   T1 (250 ms) — getJivesData.m    reads cbmex buffers, parses Jives comments
%   T2 (1 s)    — plotJivesPsychometrics.m    plots psychometrics from trials
%
% Usage:
%   1. Run this script.
%   2. Run cleanup block at the bottom when done.

%% Cleanup any previous session
if exist('T1','var') && isvalid(T1), stop(T1); delete(T1); end
if exist('T2','var') && isvalid(T2), stop(T2); delete(T2); end
cbmex('close')
clear global

%% Inputs
nFig = input('Figure number: ');

%% Global state
global trials inTrial localData
trials    = [];
inTrial   = false;
localData = [];

%% Connect
cbmex('open')
% 'comment', 200 — comment buffer size (no default documented)
cbmex('trialconfig', 1, 'double', 'absolute');%, 'comment', 200)

%% Timers
T1 = timer('Name',          'Jives_Acquire', ...
           'Period',         0.25, ...
           'ExecutionMode', 'fixedRate', ...
           'TimerFcn',       @(~,~) getJivesData(), ...
           'ErrorFcn',       @(~,e) fprintf('[T1 error] %s\n', e.Data.message));

T2 = timer('Name',          'Jives_Plot', ...
           'Period',         1.0, ...
           'ExecutionMode', 'fixedRate', ...
           'TimerFcn',       @(~,~) plotJivesPsychometrics(nFig), ...
           'ErrorFcn',       @(~,e) fprintf('[T2 error] %s\n', e.Data.message));

start(T1);
start(T2);
fprintf('Online acquisition running (fig %d). Run cleanup block to stop.\n', nFig);

%% Cleanup  (run when done)
% stop(T1); delete(T1);
% stop(T2); delete(T2);
% cbmex('trialconfig', 0);
% cbmex('close');
