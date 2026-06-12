function plotJivesPsychometrics(nFig)
% plotJivesPsychometrics  T2 plotting callback for jivesBROnline.
%
% Reads the global `trials` struct array (populated by getJivesData) and
% updates a 6-panel psychometric figure:
%
%   1. Running P(choose T1)          4. Target positions (last 50 trials)
%   2. Psychometric function          5. Reaction time distribution
%   3. Overall choice proportions     6. Trial outcome breakdown
%
% Called by jivesBROnline.m — do not call directly.

global trials

if isempty(trials) || numel(trials) < 2; return; end

%try
 %initialization
persistent fig2 dhandle dlast bhandle thandle nFit time_count ax1 htxt ...
           ax_rtL ax_rtR rtdot_L rtdot_R rtfit_L rtfit_R rtxt_L rtxt_R;
if isempty(fig2) || ~isvalid(fig2)
    fig2 = figure(nFig);
    fig2.UserData = struct('trialOffset', 0, 'doClear', false);

    ax1 = subplot(4,2,[1,2,3,4],'Parent',fig2);
    hold(ax1, 'on');
    % scatter (not animatedline) so each dot's size can encode its trial count
    dhandle  = scatter(ax1, nan, nan, 36, 'r', 'filled', 'DisplayName','Psychometric function');
    plot([0,0],[0,1],'--k');
    plot([-250,250],[0.5,0.5],'--k');

    nFit = animatedline('Color','r','LineStyle','-','LineWidth',2);

    % Black-edged ring marking the most recently updated stimulus level
    dlast = scatter(ax1, nan, nan, 36, 'r', 'filled', ...
        'MarkerEdgeColor', [0 0 0], 'LineWidth', 2, 'DisplayName','Latest level');

    xlabel('Onset time delay(s)');

    ylim([0 1]);
    yticks([0,0.5,1]);
    xlim([-250,250]);
    ylabel('Proprotion');
    title('Psychometric function', 'FontSize', 15);

    % Persistent text annotation — updated in-place each tick
    htxt = text(ax1, 0.98, 0.05, '', ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'bottom', ...
        'FontSize', 11);

    ax2 = subplot(4,2,5,'Parent',fig2);
    box off
    bhandle  = animatedline('Color','r','Marker','.','LineStyle','-','DisplayName','Bias');
    title('Bias', 'FontSize', 15)
    xlabel(ax2, 'Trial number');
    ax3 = subplot(4,2,6,'Parent',fig2);
    box off
    thandle  = animatedline('Color','r','Marker','.','LineStyle','-','DisplayName','Threshold');
    title('Treshold', 'FontSize', 15);
    xlabel(ax3, 'Trial number');

    % RT vs asynchrony — leftward onset first (stimulus_dir < 0)
    ax_rtL = subplot(4,2,7,'Parent',fig2);
    box off
    rtdot_L = animatedline(ax_rtL,'Color','b','Marker','.','MarkerSize',16,'LineStyle','none');
    rtfit_L = animatedline(ax_rtL,'Color','b','LineStyle','-','LineWidth',1.5);
    xlabel(ax_rtL,'Onset asynchrony (ms)');
    ylabel(ax_rtL,'RT (s)');
    title(ax_rtL,'RT — Leftward onset first', 'FontSize', 15);
    rtxt_L  = text(ax_rtL, 0.98, 0.95, '', 'Units','normalized', ...
        'HorizontalAlignment','right','VerticalAlignment','top','FontSize',10);

    % RT vs asynchrony — rightward onset first (stimulus_dir > 0)
    ax_rtR = subplot(4,2,8,'Parent',fig2);
    box off
    rtdot_R = animatedline(ax_rtR,'Color','r','Marker','.','MarkerSize',16,'LineStyle','none');
    rtfit_R = animatedline(ax_rtR,'Color','r','LineStyle','-','LineWidth',1.5);
    xlabel(ax_rtR,'Onset asynchrony (ms)');
    ylabel(ax_rtR,'RT (s)');
    title(ax_rtR,'RT — Rightward onset first', 'FontSize', 15);
    rtxt_R  = text(ax_rtR, 0.98, 0.95, '', 'Units','normalized', ...
        'HorizontalAlignment','right','VerticalAlignment','top','FontSize',10);

    % Clear button — top-right corner
    uicontrol(fig2, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.86, 0.965, 0.12, 0.030], ...
        'String', 'Clear', 'FontSize', 10, ...
        'BackgroundColor', [0.85 0.4 0.4], 'ForegroundColor', [1 1 1], ...
        'Callback', @(~,~) clearPsychData(fig2));

    time_count = 0;
end

% --- Handle clear request (set by button callback on previous tick) ---
if fig2.UserData.doClear
    fig2.UserData.trialOffset = numel(trials);
    fig2.UserData.doClear     = false;
    time_count = 0;
    set(dhandle,'XData',[],'YData',[]); set(dlast,'XData',[],'YData',[]); clearpoints(nFit);
    clearpoints(bhandle); clearpoints(thandle);
    clearpoints(rtdot_L); clearpoints(rtfit_L); rtxt_L.String = '';
    clearpoints(rtdot_R); clearpoints(rtfit_R); rtxt_R.String = '';
    htxt.String = '';
    drawnow;
    return;
end

% --- Apply trial offset (set by Clear button) ---
offset = fig2.UserData.trialOffset;
if offset > 0 && offset + 1 <= numel(trials)
    tAll = trials(offset+1:end);
else
    if offset >= numel(trials)
        disp('plotJivesPsychometrics: trials refreshed externally — using full trials array');
        fig2.UserData.trialOffset = 0;
    end
    tAll = trials;
end
if isempty(tAll) || numel(tAll) < 2; return; end

% --- Trials with a valid choice ---
valid  = ~isnan([tAll.Choosen_choice]);
if valid(end)==0
    return
end

tValid = tAll(valid);
if numel(tValid) < 1; return; end

% Numeric choice (1 or 2)
chooseN = [tValid.Choosen_choice]';% 1 or 2

% Target angles: right = positive, left = negative
T1xy = vertcat(tValid.Target_1_position);
%T2xy = vertcat(tValid.Target_2_position);
[th1, ~] = cart2pol(T1xy(:,1), T1xy(:,2));
T1ang = mod(90 - rad2deg(th1), 360);
T1ang(T1ang >= 180) = T1ang(T1ang >= 180) - 360;   % −180..180
direction = sign(T1ang); %1: right first, -1: left first


% Reaction time (ms)
hasRT = ~isnan([tValid.Choicetime]) & ~isnan([tValid.Fixation_point_off]);
RT    = ([tValid.Choicetime] - [tValid.Fixation_point_off])/1000; % in s

%Proportion of rightward choices
choiceLR = chooseN;
choiceLR(direction == 1 & chooseN==1) = 1; %rightward choices
choiceLR(direction == -1 & chooseN==1) = 0; %leftward choices
choiceLR(direction == -1 & chooseN==2) = 1; %rightward choices
choiceLR(direction == 1 & chooseN==2) = 0; %leftward choices

%Loop over the time asychrony
stimulus = [tValid.Requested_target_2_time_offset]';
stimulus_dir = stimulus .* direction;
[stim_levels, ~, idx] = unique(stimulus_dir);
pRight = accumarray(idx, choiceLR==1, [], @mean);

%if numel(tValid) >10
% Fitting with logistic regression
 psy = table(stimulus_dir(:), choiceLR(:), ...
            'VariableNames', {'stimulus_dir','response'});
 fitted_psy = fitglm(psy, 'response ~ stimulus_dir', 'Distribution', 'binomial');
 b0 = fitted_psy.Coefficients.Estimate(1);
 b1 = fitted_psy.Coefficients.Estimate(2);

 % Get bias and threshold
 pse = -b0 / b1;
 threshold = 1/b1;
 TotalTrials = numel(tValid);

 if abs(pse) > 500
     pse = NaN;
 end
 if abs(threshold) > 1000
     threshold = NaN;
 end

 %Fitted curve
 xx = linspace(-250, 250, 100);
 yy = 1./(1+exp(-(b0 + b1*xx)));      % fitted psy
%end

time_count = time_count + 1;

%Update the plot
% Marker size encodes trials-per-level: dots grow continuously from MIN_DOT
% at 1 trial to MAX_DOT at CLIP_TRIALS trials (clipped above that).
nPerLevel   = accumarray(idx, 1);     % # valid trials at each stimulus level
MIN_DOT     = 15;                     % scatter area at 1 trial
MAX_DOT     = 200;                    % scatter area at CLIP_TRIALS+ trials
CLIP_TRIALS = 20;                     % trial count at which size saturates
frac  = (min(nPerLevel, CLIP_TRIALS) - 1) / max(CLIP_TRIALS - 1, 1);
dotSz = MIN_DOT + (MAX_DOT - MIN_DOT) * frac;
set(dhandle, 'XData', stim_levels, 'YData', pRight, 'SizeData', dotSz);

% Outline the level updated by the most recent trial (idx(end) = its level)
iLast = idx(end);
set(dlast, 'XData', stim_levels(iLast), 'YData', pRight(iLast), 'SizeData', dotSz(iLast));

clearpoints( nFit);
addpoints( nFit, xx ,yy);


% Update annotation in-place — no accumulation, no axis-targeting issues
htxt.String = sprintf('PSE = %.1f ms\nThresh = %.1f ms\nN = %d', pse, threshold, TotalTrials);



% x-axis = actual valid-trial count (TotalTrials), not the plot-update
% counter time_count — the two diverge when >1 trial completes in one T2
% tick, which made the Bias/Threshold x lag behind the displayed N.
addpoints(bhandle, TotalTrials , pse);
addpoints(thandle, TotalTrials , threshold);

% --- RT vs asynchrony panels ---
rtCol    = RT';       % n×1
hasRTcol = hasRT';    % n×1

% Leftward onset first: stimulus_dir < 0
maskL = (stimulus_dir <= 0) & hasRTcol;
clearpoints(rtdot_L); clearpoints(rtfit_L); rtxt_L.String = '';
if sum(maskL) >= 2
    stimL = stimulus_dir(maskL);
    rtL   = rtCol(maskL);
    [levL, ~, idxL] = unique(stimL);
    meanRTL = accumarray(idxL, rtL, [], @mean);
    addpoints(rtdot_L, levL, meanRTL);
    if numel(levL) >= 2
        addpoints(rtfit_L, levL, polyval(polyfit(levL, meanRTL, 1), levL));
        [rmatL, pmatL] = corrcoef(stimL, rtL);
        rtxt_L.String = sprintf('r=%.2f  p=%.3f', rmatL(1,2), pmatL(1,2));
    end
end

% Rightward onset first: stimulus_dir > 0
maskR = (stimulus_dir >= 0) & hasRTcol;
clearpoints(rtdot_R); clearpoints(rtfit_R); rtxt_R.String = '';
if sum(maskR) >= 2
    stimR = stimulus_dir(maskR);
    rtR   = rtCol(maskR);
    [levR, ~, idxR] = unique(stimR);
    meanRTR = accumarray(idxR, rtR, [], @mean);
    addpoints(rtdot_R, levR, meanRTR);
    if numel(levR) >= 2
        addpoints(rtfit_R, levR, polyval(polyfit(levR, meanRTR, 1), levR));
        [rmatR, pmatR] = corrcoef(stimR, rtR);
        rtxt_R.String = sprintf('r=%.2f  p=%.3f', rmatR(1,2), pmatR(1,2));
    end
end

%hold off
drawnow
%{
catch
    keyboard
end
%}
end

function clearPsychData(fig)
    if ~isempty(fig) && isvalid(fig)
        fig.UserData.doClear = true;
    end
end

%{
% Outcome counts
outcomes    = {tValid.Trialoutcome};
outcomeList = {'Correct','Time out','Broke fixation'};
outCount    = cellfun(@(o) sum(strcmp(outcomes, o)), outcomeList);

%% --- Draw ---
figure(nFig); clf;
nRows = 2; nCols = 3;

% 1. Running P(choose T1)
subplot(nRows, nCols, 1); cla; hold on
window     = 20;
pT1running = movmean(chooseN == 1, min(window, numel(chooseN)));
plot(pT1running, 'LineWidth', 1.5)
yline(0.5, '--k')
ylim([0 1])
xlabel('Trial'); ylabel('P(choose T1)')
title(sprintf('Running P(T1)  [win=%d]', window))

% 2. Psychometric function: P(choose T1) by T1 angle
subplot(nRows, nCols, 2); cla; hold on
angs   = unique(T1ang);
pByAng = arrayfun(@(a) mean(chooseN(T1ang == a) == 1), angs);
nByAng = arrayfun(@(a) sum(T1ang == a), angs);
scatter(angs, pByAng, 30 + nByAng*3, 'filled')
plot(angs, pByAng, '-', 'Color', [0.5 0.5 0.5])
yline(0.5, '--k')
xlim([-180 180]); ylim([0 1])
xlabel('T1 angle (deg)'); ylabel('P(choose T1)')
title('Psychometric function')

% 3. Overall choice proportions
subplot(nRows, nCols, 3); cla
nT1 = sum(chooseN == 1);
nT2 = sum(chooseN == 2);
bar([nT1, nT2], 'FaceColor', [0.4 0.6 0.8])
set(gca, 'XTickLabel', {'Target 1','Target 2'})
ylabel('# choices')
title(sprintf('T1: %d (%.0f%%)   T2: %d (%.0f%%)', ...
    nT1, 100*nT1/(nT1+nT2), nT2, 100*nT2/(nT1+nT2)))

% 4. Target positions (last 50 trials), red = chosen
subplot(nRows, nCols, 4); cla; hold on; axis equal
n2plot = min(50, numel(tValid));
idx    = numel(tValid)-n2plot+1 : numel(tValid);
chN    = chooseN(idx);
scatter(T1xy(idx,1), T1xy(idx,2), 30, (chN==1)*[1 0 0] + (chN~=1)*[0 0 0], 'filled')
scatter(T2xy(idx,1), T2xy(idx,2), 30, (chN==2)*[1 0 0] + (chN~=2)*[0 0 0], 'filled')
plot([-20 20],[0 0],'k'); plot([0 0],[-20 20],'k')
xlabel('X (deg)'); ylabel('Y (deg)')
title(sprintf('Target locations (red = chosen, last %d)', n2plot))

% 5. Reaction time distribution
subplot(nRows, nCols, 5); cla
if sum(hasRT) > 3
    histogram(RT(hasRT), 20)
    xlabel('RT (ms)'); ylabel('# trials')
    title(sprintf('RT  median = %.0f ms', median(RT(hasRT))))
else
    axis off
    text(0.3, 0.5, 'Waiting for RT data...', 'Units','normalized')
end

% 6. Trial outcome breakdown
subplot(nRows, nCols, 6); cla
bar(outCount, 'FaceColor', [0.7 0.7 0.7])
set(gca, 'XTickLabel', outcomeList, 'XTickLabelRotation', 15)
ylabel('# trials')
title(sprintf('Total: %d trials', numel(trials)))

drawnow
%}
