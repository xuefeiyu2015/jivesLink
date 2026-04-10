function plotJivesVisualSaccade(nFig)
% plotJivesVisualSaccade  Online plots for the Visual Saccade task.
%
% Stub — implement analysis here.
% Called by jivesAnalysisSwitchyard every 1 s (T2 timer).

global trials
if isempty(trials); return; end

figure(nFig);
clf;
title(sprintf('Visual Saccade Task  —  %d trials', numel(trials)));
