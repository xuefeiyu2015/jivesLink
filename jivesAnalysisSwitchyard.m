function jivesAnalysisSwitchyard(nFig)
% jivesAnalysisSwitchyard  T2 dispatch — selects analysis based on task type.
%
% Always calls plotJivesDashboard(nFig+1) for the session overview, then
% dispatches to the task-specific plot based on trials(end).task_type:
%
%   Fixation task            -> plotJivesFixation(nFig)
%   Visual Saccade Task      -> plotJivesVisualSaccade(nFig)
%   Time discrimination task -> plotJivesPsychometrics(nFig)
%
% Called by T2 timer every 1 s. Do not call directly.

global trials

if isempty(trials)
    return
end

% Session dashboard — always updated regardless of task type
plotJivesDashboard(nFig + 1);

% Find most recent trial that has a task_type set
task_type = '';
for k = numel(trials):-1:1
    if ischar(trials(k).task_type) && ~isempty(trials(k).task_type)
        task_type = trials(k).task_type;
        break
    end
end

if isempty(task_type)
    return
end

switch task_type
    case 'Fixation task'
        plotJivesFixation(nFig);

    case 'Visual Saccade Task'
        plotJivesVisualSaccade(nFig);

    case 'Time discrimination task'
        plotJivesPsychometrics(nFig);

    otherwise
        fprintf('[Switchyard] Unknown task type: "%s"\n', task_type);
end
