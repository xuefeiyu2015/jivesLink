function plotJivesDashboard(nFig)
% plotJivesDashboard  Session-wide overview, updated every T2 tick (1 s).
%
% Four line plots — running proportion relative to total trials in buffer:
%   (1,1) Successful trials
%   (1,2) Break fixation trials
%   (2,1) Time out trials
%   (2,2) Rightward choices (Time discrimination task only)
%
% Called by jivesAnalysisSwitchyard every 1 s. Do not call directly.

global trials
if isempty(trials); return; end

n_total = numel(trials);

%% Build per-trial outcome vectors — vectorized over outcome strings
outcomes    = {trials.Trialoutcome};
has_outcome = cellfun(@ischar, outcomes);          % exclude trials where Trialoutcome is still NaN
oc          = lower(outcomes);
oc(~has_outcome) = {''};                           % make NaN entries harmless for contains

is_breakfix = cellfun(@(x) contains(x,'break') || contains(x,'fixat'), oc);
is_timeout  = cellfun(@(x) contains(x,'time'),  oc);
is_correct  = cellfun(@(x) contains(x,'correct'), oc);
is_incorrect  = cellfun(@(x) contains(x,'incorrect'));
is_success  = has_outcome & (is_correct |is_incorrect);

% Rightward choice — all tasks, vectorized
has_choice = cellfun(@(x) ischar(x) && ~isempty(x), {trials.Choosen_choice});

t1x = arrayfun(@(t) t.Target_1_position(1), trials);
t2x = arrayfun(@(t) t.Target_2_position(1), trials);

chosen_n             = nan(1, n_total);
chosen_n(has_choice) = cellfun(@str2double, {trials(has_choice).Choosen_choice});

pos_x                = nan(1, n_total);
pos_x(chosen_n == 1) = t1x(chosen_n == 1);
pos_x(chosen_n == 2) = t2x(chosen_n == 2);

has_right = has_choice & ~isnan(pos_x);
is_right  = pos_x > 0;

%% Bin trials by minute
t0       = trials(1).Start;                              % session start time (s)
minutes  = floor(([trials.Start] - t0) / 60);           % which minute each trial belongs to
bins     = 0 : max(minutes);                             % minute indices
n_bins   = numel(bins);

bin_idx = minutes + 1;   % accumarray needs 1-based indices

n_per_bin     = accumarray(bin_idx', true(1,n_total)',  [n_bins 1])';
prop_success  = accumarray(bin_idx', is_success',       [n_bins 1])' ./ n_per_bin * 100;
prop_breakfix = accumarray(bin_idx', is_breakfix',      [n_bins 1])' ./ n_per_bin * 100;
prop_timeout  = accumarray(bin_idx', is_timeout',       [n_bins 1])' ./ n_per_bin * 100;
prop_correct  = accumarray(bin_idx', is_correct',       [n_bins 1])' ./ n_per_bin * 100;

n_choice_per_bin = accumarray(bin_idx', has_right',  [n_bins 1])';
prop_right       = accumarray(bin_idx', is_right',   [n_bins 1])' ./ n_choice_per_bin * 100;
prop_right(n_choice_per_bin == 0) = nan;

x_bins = bins + 1;   % display as minute 1, 2, 3, ...

%% Plot
if ~ishandle(nFig)
    figure(nFig);
    set(nFig, 'Position', [100 100 900 600]);
else
    figure(nFig);
end

subplot(1, 2, 1);
plot(x_bins, prop_success,  'k-', 'LineWidth', 1.5); hold on;
plot(x_bins, prop_correct,  'g-', 'LineWidth', 1.5);
plot(x_bins, prop_breakfix, 'r-', 'LineWidth', 1.5);
plot(x_bins, prop_timeout,  'm-', 'LineWidth', 1.5); hold off;
ylim([0 100]);  xlabel('Minute');  ylabel('%');
legend('Successful', 'Correct', 'Break fix', 'Timeout', 'Location', 'best');
title(sprintf('Outcomes  (%d trials)', n_total));

subplot(1, 2, 2);
if any(~isnan(prop_right))
    plot(x_bins, prop_right, 'b-', 'LineWidth', 1.5);
    hold on;  yline(50, '--k');  hold off;
    ylim([0 100]);  xlabel('Minute');  ylabel('%');
    title(sprintf('Rightward choices  (%d trials)', sum(has_right)));
else
    cla;
    text(0.5, 0.5, 'No choice trials yet', ...
        'HorizontalAlignment', 'center', 'Units', 'normalized', 'Color', [0.5 0.5 0.5]);
    title('Rightward choices');
end

sgtitle(sprintf('Session dashboard  —  %d trials total', n_total));
