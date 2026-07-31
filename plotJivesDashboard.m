function plotJivesDashboard(nFig)
% plotJivesDashboard  Session-wide overview.
%
% Four line plots — running proportion over a rolling window of the last N
% completed trials:
%   red     Correct trials
%   blue    Break fixation trials
%   yellow  Time out trials
%   magenta Successful trials (correct + wrong, i.e. the animal made a choice)
%
% Reads the numeric mirror `tsum` rather than the `trials` struct array, so
% the per-tick cost is independent of how long the session has run.
%
% Called by jivesAnalysisSwitchyard every 1 s. Do not call directly.
% Does NOT call drawnow — the switchyard issues a single flush per tick.

global tsum;

if isempty(tsum) || tsum.n == 0
    return
end

persistent fig chandle shandle bhandle thandle time_count;

%initialization
if isempty(fig) || ~isvalid(fig)
    fig = figure(nFig);
    chandle  = animatedline('Color','r','Marker','o','LineStyle','-','LineWidth',1.5,'DisplayName','Correct Trial');
    hold on
    bhandle  = animatedline('Color','b','Marker','o','LineStyle','-','LineWidth',1.5,'DisplayName','BrokeFix Trial');
    thandle  = animatedline('Color','y','Marker','o','LineStyle','-','LineWidth',1.5,'DisplayName','Timeout Trial');
    shandle  = animatedline('Color','m','Marker','o','LineStyle','-','LineWidth',1.5,'DisplayName','Successful Trial');
    xlabel('Time(s)');
    ylim([0,1]);
    ylabel('Proprotion');
    title('Performance over time');
    legend('show','Location','southwestoutside');
    time_count = 0;
end

time_count = time_count + 1;

% --- Rolling window over the last N completed trials ---------------------
% Slice the preallocated numeric arrays directly. The previous version built
% {trials.Trialoutcome} across the WHOLE session and then discarded all but
% the last N values, which grew linearly with session length for no benefit.
N  = 20;
i1 = max(tsum.n - N + 1, 1);
w  = tsum.outcome(i1 : tsum.n);

total_trial = numel(w);
if total_trial == 0
    return
end

% Outcome bitmask (set in getJivesData/outcomeMask):
%   bit 1 = correct, bit 2 = broke, bit 3 = timeout, bit 4 = wrong.
% Independent bits, matching the four separate contains() tests this plot
% used to run over the outcome strings.
nCorrect = sum(bitand(w, uint8(1)) > 0);
nBroke   = sum(bitand(w, uint8(2)) > 0);
nTimeout = sum(bitand(w, uint8(4)) > 0);
nWrong   = sum(bitand(w, uint8(8)) > 0);

prop_correct       = nCorrect / total_trial;
prop_breakfix      = nBroke   / total_trial;
prop_timeout_trial = nTimeout / total_trial;
prop_suc           = (nCorrect + nWrong) / total_trial;

%Update the plot
addpoints(chandle, time_count, prop_correct);
addpoints(bhandle, time_count, prop_breakfix);
addpoints(thandle, time_count, prop_timeout_trial);
addpoints(shandle, time_count, prop_suc);
