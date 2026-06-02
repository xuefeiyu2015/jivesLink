function plotJivesDashboard(nFig)
% plotJivesDashboard  Session-wide overview.
%
% Four line plots — running proportion relative to total trials in buffer:
%   red Successful trials
%   (1,2) Break fixation trials
%   (2,1) Time out trials
%   (2,2) Rightward choices (Time discrimination task only)
%
% Called by jivesAnalysisSwitchyard every 1 s. Do not call directly.


% Append new trial if one arrived since last tick

global trials;

if isempty(trials)
    return
end
persistent fig chandle shandle bhandle thandle time_count;


%initialization
if isempty(fig) ||~isvalid(fig) || time_count==0
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

time_count= time_count+1;
%Get the current trial outcome
outcomes    = {trials.Trialoutcome};

%Get the past N trials
N = 20;

outcome_seq = outcomes(max(length(outcomes)-N,1)+1:end);
total_trial = length(outcome_seq);
corr_trial = cellfun(@(x) contains(x,'correct'),outcome_seq);
prop_correct = sum(corr_trial)/total_trial;
breakfix_trial = cellfun(@(x) contains(x,'broke'),outcome_seq);
prop_breakfix = sum(breakfix_trial)/total_trial;
error_trial =  cellfun(@(x) contains(x,'wrong'),outcome_seq);
prop_suc = (sum(corr_trial)+sum(error_trial))/total_trial;

timeout_trial = cellfun(@(x) contains(x,'timeout'),outcome_seq);
prop_timeout_trial = sum(timeout_trial)/total_trial;

%Update the plot
addpoints(chandle, time_count ,prop_correct);
addpoints(bhandle, time_count ,prop_breakfix);
addpoints(thandle, time_count ,prop_timeout_trial);
addpoints(shandle, time_count ,prop_suc);
drawnow

