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
           ax_rtL ax_rtR rtdot_L rtdot_R rtfit_L rtfit_R rtxt_L rtxt_R ...
           rtlast_L rtlast_R rtx_L rtx_R;
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
    hold(ax_rtL, 'on');
    % scatter (not animatedline) so dot size can encode trials-per-level
    rtdot_L = scatter(ax_rtL, nan, nan, 36, 'b', 'filled');               % leftward choice (congruent)
    rtfit_L = animatedline(ax_rtL,'Color','b','LineStyle','-','LineWidth',1.5);
    rtx_L   = scatter(ax_rtL, nan, nan, 36, 'b', 'x', 'LineWidth', 1.8);  % rightward choice (cross)
    rtlast_L = scatter(ax_rtL, nan, nan, 36, 'MarkerEdgeColor',[0 0 0], ...
        'MarkerFaceColor','none', 'LineWidth', 2);     % hollow latest-trial ring
    xlabel(ax_rtL,'Onset asynchrony (ms)');
    ylabel(ax_rtL,'RT (s)');
    title(ax_rtL,'RT — Leftward onset first', 'FontSize', 15);
    rtxt_L  = text(ax_rtL, 0.98, 0.95, '', 'Units','normalized', ...
        'HorizontalAlignment','right','VerticalAlignment','top','FontSize',10);

    % RT vs asynchrony — rightward onset first (stimulus_dir > 0)
    ax_rtR = subplot(4,2,8,'Parent',fig2);
    box off
    hold(ax_rtR, 'on');
    % scatter (not animatedline) so dot size can encode trials-per-level
    rtdot_R = scatter(ax_rtR, nan, nan, 36, 'r', 'filled');               % rightward choice (congruent)
    rtfit_R = animatedline(ax_rtR,'Color','r','LineStyle','-','LineWidth',1.5);
    rtx_R   = scatter(ax_rtR, nan, nan, 36, 'r', 'x', 'LineWidth', 1.8);  % leftward choice (cross)
    rtlast_R = scatter(ax_rtR, nan, nan, 36, 'MarkerEdgeColor',[0 0 0], ...
        'MarkerFaceColor','none', 'LineWidth', 2);     % hollow latest-trial ring
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
    set(rtdot_L,'XData',[],'YData',[]); set(rtx_L,'XData',[],'YData',[]); set(rtlast_L,'XData',[],'YData',[]); clearpoints(rtfit_L); rtxt_L.String = '';
    set(rtdot_R,'XData',[],'YData',[]); set(rtx_R,'XData',[],'YData',[]); set(rtlast_R,'XData',[],'YData',[]); clearpoints(rtfit_R); rtxt_R.String = '';
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

% --- Trials with a valid choice AND from the time-discrimination task ---
% Mirror the switchyard's dispatch predicate (contains(Task,'time')) so the
% psychometric never mixes in trials from other tasks (e.g. visual saccade),
% whose Requested_target_2_time_offset is NaN and would pollute the fit.
isTimeTask = arrayfun(@(t) contains(t.Task, 'time'), tAll);
valid      = ~isnan([tAll.Choosen_choice]) & isTimeTask;
if isempty(valid) || valid(end)==0
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

TotalTrials = numel(tValid);

% Fit only once BOTH onset-first conditions exist (points on both sides of
% zero asynchrony) — a sigmoid is unconstrained otherwise.
canFitPsy = any(stimulus_dir < 0) && any(stimulus_dir > 0);

if canFitPsy
    % Constrained logistic MLE: parameterise the slope as b1 = exp(g), so the
    % slope is POSITIVE by construction and the psychometric can never fit
    % "reversed" (negative slope / negative threshold). Unconstrained ML over
    % [b0, g] via fminsearch (base MATLAB) on the Bernoulli neg-log-likelihood.
    x = stimulus_dir(:);
    y = double(choiceLR(:) == 1);            % 1 = rightward choice

    % Numerically stable softplus: log(1+exp(z)) without overflow.
    softplus = @(z) max(z,0) + log1p(exp(-abs(z)));
    nll = @(p) sum( softplus(p(1) + exp(p(2)).*x) - y.*(p(1) + exp(p(2)).*x) );

    % Adaptive iteration cap: few trials -> few iterations (fast, rough),
    % growing as data accumulates for a more accurate fit later.
    maxIter = min(400, 60 + 4*TotalTrials);
    optz = optimset('MaxIter', maxIter, 'MaxFunEvals', 2*maxIter, 'Display','off');

    p0   = [0, log(0.02)];                    % start: zero bias, gentle slope
    pHat = fminsearch(nll, p0, optz);

    b0 = pHat(1);
    b1 = exp(pHat(2));                        % > 0 by construction
    validFit = isfinite(b0) && isfinite(b1) && b1 > 0;
else
    validFit = false;
    b0 = NaN; b1 = NaN;
end

if validFit
    % Get bias and threshold
    pse = -b0 / b1;
    threshold = 1/b1;
    if abs(pse) > 500
        pse = NaN;
    end
    if abs(threshold) > 1000
        threshold = NaN;
    end

    %Fitted curve
    xx = linspace(-250, 250, 100);
    yy = 1./(1+exp(-(b0 + b1*xx)));      % fitted psy
else
    pse = NaN; threshold = NaN; xx = []; yy = [];
end

time_count = time_count + 1;

%Update the plot
% Marker size encodes trials-per-level (shared rule in trialCountDotSize)
nPerLevel = accumarray(idx, 1);       % # valid trials at each stimulus level
dotSz     = trialCountDotSize(nPerLevel);
set(dhandle, 'XData', stim_levels, 'YData', pRight, 'SizeData', dotSz);

% Outline the level updated by the most recent trial (idx(end) = its level)
iLast = idx(end);
set(dlast, 'XData', stim_levels(iLast), 'YData', pRight(iLast), 'SizeData', dotSz(iLast));

clearpoints( nFit);
if ~isempty(xx)
    addpoints( nFit, xx ,yy);
end

% Update annotation in-place — no accumulation, no axis-targeting issues
if validFit
    htxt.String = sprintf('PSE = %.1f ms\nThresh = %.1f ms\nN = %d', pse, threshold, TotalTrials);
else
    htxt.String = sprintf('collecting data...\nN = %d', TotalTrials);
end


% x-axis = actual valid-trial count (TotalTrials), not the plot-update
% counter time_count — the two diverge when >1 trial completes in one T2
% tick, which made the Bias/Threshold x lag behind the displayed N.
% Only append valid (positive-slope) fits so the series has no NaN gaps.
if validFit
    addpoints(bhandle, TotalTrials , pse);
    addpoints(thandle, TotalTrials , threshold);
end

% --- RT vs asynchrony panels ---
rtCol    = RT';       % n×1
hasRTcol = hasRT';    % n×1

% choiceLR: 1 = rightward choice, 0 = leftward choice
% Each panel: choice MATCHING the onset-first side -> filled dots + fit;
% the opposite choice -> cross markers (no fit).
RT_FIT_MIN = 6;   % min trials in a choice group before its RT line is drawn

% --- Leftward onset first (stimulus_dir <= 0) ---
inL    = (stimulus_dir <= 0) & hasRTcol;
fillL  = inL & (choiceLR == 0);    % leftward choice  -> filled dots + fit
crossL = inL & (choiceLR == 1);    % rightward choice -> cross marker
[levFL, mrtFL, nFL] = rtByLevel(stimulus_dir, rtCol, fillL);
[levXL, mrtXL, nXL] = rtByLevel(stimulus_dir, rtCol, crossL);

set(rtdot_L,'XData',[],'YData',[]); set(rtx_L,'XData',[],'YData',[]);
set(rtlast_L,'XData',[],'YData',[]); clearpoints(rtfit_L); rtxt_L.String = '';

if ~isempty(levFL)
    set(rtdot_L,'XData',levFL,'YData',mrtFL,'SizeData',trialCountDotSize(nFL));
    if numel(levFL) >= 2 && sum(fillL) >= RT_FIT_MIN
        addpoints(rtfit_L, levFL, polyval(polyfit(levFL, mrtFL, 1), levFL));
        [rmatL, pmatL] = corrcoef(stimulus_dir(fillL), rtCol(fillL));
        rtxt_L.String = sprintf('r=%.2f  p=%.3f', rmatL(1,2), pmatL(1,2));
    end
end
if ~isempty(levXL)
    set(rtx_L,'XData',levXL,'YData',mrtXL,'SizeData',crossDotSize(nXL));
end
% encircle the most recent trial's point, on whichever group it belongs to
if hasRTcol(end) && stimulus_dir(end) <= 0
    if choiceLR(end) == 0
        ringRT(rtlast_L, levFL, mrtFL, nFL, stimulus_dir(end), @trialCountDotSize);
    else
        ringRT(rtlast_L, levXL, mrtXL, nXL, stimulus_dir(end), @crossDotSize);
    end
end

% --- Rightward onset first (stimulus_dir >= 0) ---
inR    = (stimulus_dir >= 0) & hasRTcol;
fillR  = inR & (choiceLR == 1);    % rightward choice -> filled dots + fit
crossR = inR & (choiceLR == 0);    % leftward choice  -> cross marker
[levFR, mrtFR, nFR] = rtByLevel(stimulus_dir, rtCol, fillR);
[levXR, mrtXR, nXR] = rtByLevel(stimulus_dir, rtCol, crossR);

set(rtdot_R,'XData',[],'YData',[]); set(rtx_R,'XData',[],'YData',[]);
set(rtlast_R,'XData',[],'YData',[]); clearpoints(rtfit_R); rtxt_R.String = '';

if ~isempty(levFR)
    set(rtdot_R,'XData',levFR,'YData',mrtFR,'SizeData',trialCountDotSize(nFR));
    if numel(levFR) >= 2 && sum(fillR) >= RT_FIT_MIN
        addpoints(rtfit_R, levFR, polyval(polyfit(levFR, mrtFR, 1), levFR));
        [rmatR, pmatR] = corrcoef(stimulus_dir(fillR), rtCol(fillR));
        rtxt_R.String = sprintf('r=%.2f  p=%.3f', rmatR(1,2), pmatR(1,2));
    end
end
if ~isempty(levXR)
    set(rtx_R,'XData',levXR,'YData',mrtXR,'SizeData',crossDotSize(nXR));
end
if hasRTcol(end) && stimulus_dir(end) >= 0
    if choiceLR(end) == 1
        ringRT(rtlast_R, levFR, mrtFR, nFR, stimulus_dir(end), @trialCountDotSize);
    else
        ringRT(rtlast_R, levXR, mrtXR, nXR, stimulus_dir(end), @crossDotSize);
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

function sz = trialCountDotSize(n)
% Scatter marker area scaling continuously from MIN_DOT at 1 trial to
% MAX_DOT at CLIP_TRIALS trials (clipped above that). Shared by the
% psychometric and the RT-vs-asynchrony panels.
MIN_DOT     = 15;                      % scatter area at 1 trial
MAX_DOT     = 200;                     % scatter area at CLIP_TRIALS+ trials
CLIP_TRIALS = 20;                      % trial count at which size saturates
frac = (min(n(:), CLIP_TRIALS) - 1) / max(CLIP_TRIALS - 1, 1);
sz   = MIN_DOT + (MAX_DOT - MIN_DOT) * frac;
end

function [lev, mrt, n] = rtByLevel(stim, rt, mask)
% Mean RT and trial count per unique asynchrony level, over the masked trials.
s = stim(mask);  r = rt(mask);
if isempty(s)
    lev = [];  mrt = [];  n = [];
    return;
end
[lev, ~, ix] = unique(s);
mrt = accumarray(ix, r, [], @mean);
n   = accumarray(ix, 1);
end

function sz = crossDotSize(n)
% Cross markers get a higher floor than filled dots so a single-trial
% cross stays clearly visible.
MIN_CROSS = 60;
sz = max(trialCountDotSize(n), MIN_CROSS);
end

function s = ringSize(markerArea)
% Hollow ring area that encircles (sits outside) a marker of markerArea.
s = markerArea*2 + 40;
end

function ringRT(h, lev, mrt, n, x, sizeFcn)
% Position the hollow latest-trial ring h at asynchrony level x (if present),
% sized to encircle a marker drawn with sizeFcn (trialCountDotSize/crossDotSize).
i = find(lev == x, 1);
if ~isempty(i)
    set(h, 'XData', lev(i), 'YData', mrt(i), 'SizeData', ringSize(sizeFcn(n(i))));
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
