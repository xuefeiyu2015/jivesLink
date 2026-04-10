function plotJivesFixation(nFig)
% plotJivesFixation  Online plots for the Fixation task.
%
% Stub — implement analysis here.
% Called by jivesAnalysisSwitchyard every 1 s (T2 timer).

global trials
if isempty(trials); return; end

figure(nFig);
clf;
title(sprintf('Fixation task  —  %d trials', numel(trials)));
