function plotJivesReceptiveField(nFig)
% plotJivesReceptiveField  Online RF heatmap and PSTHs per sorted unit.
%
% Layout (three rows below the channel/unit dropdowns):
%   Row 1 — Gaussian-smoothed FR heatmap (50-250 ms post-target).
%            Tested target positions overlaid as white circles.
%   Row 2 — PSTH aligned on visual onset  (Target_1_presented).
%   Row 3 — PSTH aligned on go signal     (Fixation_point_off).
%
% One column per active sorted unit on the selected channel.
% Called every T2 tick by jivesAnalysisSwitchyard for saccade tasks.

global trials

% ── Constants ─────────────────────────────────────────────────────────────
RF_WIN_MS    = [50 250];
SMOOTH_SIGMA = 2.5;           % bins (= deg), RF Gaussian blur
GRID_EDGES   = -20:1:20;
GRID_CTRS    = (GRID_EDGES(1:end-1) + GRID_EDGES(2:end)) / 2;
FIX_COLOR    = [1 0 0];
CTRL_H       = 60;            % px reserved at top for dropdowns

VIS_WIN_MS   = [-200, 600];   % ms, aligned to Target_1_presented
GO_WIN_MS    = [-400, 300];   % ms, aligned to Fixation_point_off
BIN_MS       = 10;            % ms per PSTH bin
PSTH_SIGMA   = 20;            % ms, Gaussian PSTH smoothing

% ── Persistent state ──────────────────────────────────────────────────────
persistent fig hChDD hUnitDD ...
           hRFt0 hRFt1 hVist0 hVist1 hGot0 hGot1 ...
           pRF pVis pGo ...
           axRF axVis axGo ...
           lastCh lastUnitSel lastNCh lastNUnits

if isempty(trials); return; end

% Read channel/unit selection from dropdowns (or defaults before figure exists)
if isempty(fig) || ~isvalid(fig)
    chSel   = 1;
    unitSel = -1;
    rfWin   = RF_WIN_MS;
    visWin  = VIS_WIN_MS;
    goWin   = GO_WIN_MS;
else
    chSel = hChDD.Value;
    if hUnitDD.Value == numel(hUnitDD.String)
        unitSel = -1;
    else
        unitSel = hUnitDD.Value;
    end
    rfWin  = [str2double(hRFt0.String),  str2double(hRFt1.String)];
    visWin = [str2double(hVist0.String), str2double(hVist1.String)];
    goWin  = [str2double(hGot0.String),  str2double(hGot1.String)];
    if any(isnan(rfWin));  rfWin  = RF_WIN_MS;  end
    if any(isnan(visWin)); visWin = VIS_WIN_MS; end
    if any(isnan(goWin));  goWin  = GO_WIN_MS;  end
end

% ── Build figure once ─────────────────────────────────────────────────────
if isempty(fig) || ~isvalid(fig)
    fig = figure(nFig);
    clf(fig);
    set(fig, 'Position',[200 50 1200 900], 'Name','Jives RF Plot', ...
             'NumberTitle','off');
    figH = fig.Position(4);
    fc   = CTRL_H / figH;   % fraction used by controls
    fd   = 1 - fc;          % fraction available for data rows

    % Dropdowns
    uicontrol(fig,'Style','text','Units','pixels', ...
        'Position',[20 figH-CTRL_H+20 35 22], ...
        'String','Ch:','HorizontalAlignment','right','FontSize',11);
    hChDD = uicontrol(fig,'Style','popupmenu','Units','pixels', ...
        'Position',[60 figH-CTRL_H+22 80 22], ...
        'String',arrayfun(@num2str,1:96,'uni',0), ...
        'Value',chSel,'FontSize',11, ...
        'Callback',@(~,~) plotJivesReceptiveField(nFig));
    uicontrol(fig,'Style','text','Units','pixels', ...
        'Position',[160 figH-CTRL_H+20 45 22], ...
        'String','Unit:','HorizontalAlignment','right','FontSize',11);
    hUnitDD = uicontrol(fig,'Style','popupmenu','Units','pixels', ...
        'Position',[210 figH-CTRL_H+22 80 22], ...
        'String',{'all'}, ...
        'Value',1,'FontSize',11, ...
        'Callback',@(~,~) plotJivesReceptiveField(nFig));

    % Time-window edit boxes  ── RF | Vis | Go ────────────────────────────
    CB = @(~,~) plotJivesReceptiveField(nFig);   % shared replot callback
    y  = figH - CTRL_H + 20;   % label baseline
    ye = figH - CTRL_H + 22;   % edit baseline

    uicontrol(fig,'Style','text','Units','pixels','Position',[315 y 28 22], ...
        'String','RF:','HorizontalAlignment','right','FontSize',10);
    hRFt0 = uicontrol(fig,'Style','edit','Units','pixels','Position',[347 ye 50 22], ...
        'String',num2str(RF_WIN_MS(1)),'FontSize',10,'Callback',CB);
    uicontrol(fig,'Style','text','Units','pixels','Position',[400 y 18 22], ...
        'String','to','FontSize',10);
    hRFt1 = uicontrol(fig,'Style','edit','Units','pixels','Position',[421 ye 50 22], ...
        'String',num2str(RF_WIN_MS(2)),'FontSize',10,'Callback',CB);
    uicontrol(fig,'Style','text','Units','pixels','Position',[474 y 22 22], ...
        'String','ms','FontSize',10);

    uicontrol(fig,'Style','text','Units','pixels','Position',[520 y 30 22], ...
        'String','Vis:','HorizontalAlignment','right','FontSize',10);
    hVist0 = uicontrol(fig,'Style','edit','Units','pixels','Position',[554 ye 55 22], ...
        'String',num2str(VIS_WIN_MS(1)),'FontSize',10,'Callback',CB);
    uicontrol(fig,'Style','text','Units','pixels','Position',[613 y 18 22], ...
        'String','to','FontSize',10);
    hVist1 = uicontrol(fig,'Style','edit','Units','pixels','Position',[634 ye 55 22], ...
        'String',num2str(VIS_WIN_MS(2)),'FontSize',10,'Callback',CB);
    uicontrol(fig,'Style','text','Units','pixels','Position',[692 y 22 22], ...
        'String','ms','FontSize',10);

    uicontrol(fig,'Style','text','Units','pixels','Position',[735 y 28 22], ...
        'String','Go:','HorizontalAlignment','right','FontSize',10);
    hGot0 = uicontrol(fig,'Style','edit','Units','pixels','Position',[767 ye 55 22], ...
        'String',num2str(GO_WIN_MS(1)),'FontSize',10,'Callback',CB);
    uicontrol(fig,'Style','text','Units','pixels','Position',[826 y 18 22], ...
        'String','to','FontSize',10);
    hGot1 = uicontrol(fig,'Style','edit','Units','pixels','Position',[847 ye 55 22], ...
        'String',num2str(GO_WIN_MS(2)),'FontSize',10,'Callback',CB);
    uicontrol(fig,'Style','text','Units','pixels','Position',[905 y 22 22], ...
        'String','ms','FontSize',10);

    % Three equal-height row panels (bottom→top in normalised coords)
    bgc = get(fig,'Color');
    pGo  = uipanel(fig,'Units','normalized','Position',[0,  0,         1, fd/3], ...
                   'BorderType','none','BackgroundColor',bgc);
    pVis = uipanel(fig,'Units','normalized','Position',[0,  fd/3,      1, fd/3], ...
                   'BorderType','none','BackgroundColor',bgc);
    pRF  = uipanel(fig,'Units','normalized','Position',[0,  fd*2/3,    1, fd/3], ...
                   'BorderType','none','BackgroundColor',bgc);

    axRF = gobjects(0);  axVis = gobjects(0);  axGo = gobjects(0);
    lastCh = [];  lastUnitSel = [];  lastNCh = [];  lastNUnits = [];
end

% ── Refresh channel/unit dropdowns if spike grid grew ─────────────────────
if ~isempty(trials(end).spike_times)
    nCh = size(trials(end).spike_times, 1);
    if isempty(lastNCh) || lastNCh ~= nCh
        hChDD.String = arrayfun(@num2str, 1:nCh, 'uni', 0);
        hChDD.Value  = min(chSel, nCh);
        chSel        = hChDD.Value;
        lastNCh      = nCh;
    end

    % Cols 1-2 are unsorted/hash; sorted units start at col 3
    nSortedUnits = max(0, size(trials(end).spike_times, 2) - 2);
    if isempty(lastNUnits) || lastNUnits ~= nSortedUnits
        unitStrs = [arrayfun(@num2str, 1:nSortedUnits, 'uni', 0), {'all'}];
        prevVal  = hUnitDD.Value;
        hUnitDD.String = unitStrs;
        hUnitDD.Value  = min(prevVal, numel(unitStrs));
        lastNUnits = nSortedUnits;
    end
end

% Re-read unitSel after potential dropdown update
if ~isempty(fig) && isvalid(fig)
    if hUnitDD.Value == numel(hUnitDD.String)
        unitSel = -1;
    else
        unitSel = hUnitDD.Value;
    end
end

% ── Resolve which unit columns to plot ────────────────────────────────────
if unitSel == -1
    nUcols = 0;
    for n = 1:numel(trials)
        if ~isempty(trials(n).spike_times) && chSel <= size(trials(n).spike_times,1)
            nUcols = max(nUcols, size(trials(n).spike_times,2));
        end
    end
    activeMask = false(1, max(nUcols,2));
    for u = 3:nUcols
        for n = 1:numel(trials)
            sp = trials(n).spike_times;
            if ~isempty(sp) && chSel<=size(sp,1) && u<=size(sp,2) && ~isempty(sp{chSel,u})
                activeMask(u) = true;  break
            end
        end
    end
    unitCols = find(activeMask);
    if isempty(unitCols); unitCols = 3; end
else
    unitCols = 2 + unitSel;
end
nU = numel(unitCols);

% ── RF grid accumulation ───────────────────────────────────────────────────
nG     = numel(GRID_EDGES) - 1;
gridFR = cell(nU,1);
gridN  = cell(nU,1);
for k = 1:nU
    gridFR{k} = nan(nG,nG);
    gridN{k}  = zeros(nG,nG);
end
winSec = rfWin / 1000;
winDur = diff(rfWin) / 1000;

for n = 1:numel(trials)
    if ~ischar(trials(n).Trialoutcome) || ~contains(trials(n).Trialoutcome,'correct')
        continue
    end
    sp = trials(n).spike_times;
    if isempty(sp) || chSel > size(sp,1);  continue;  end
    for kt = 1:2
        t0 = trials(n).(sprintf('Target_%d_presented',kt));
        xy = trials(n).(sprintf('Target_%d_position', kt));
        if isnan(t0) || any(isnan(xy));  continue;  end
        ix = discretize(xy(1), GRID_EDGES);
        iy = discretize(xy(2), GRID_EDGES);
        if isnan(ix) || isnan(iy);  continue;  end
        w = t0 + winSec;
        for k = 1:nU
            u = unitCols(k);
            if u > size(sp,2);  continue;  end
            ts_u = sp{chSel,u};
            fr   = sum(ts_u >= w(1) & ts_u <= w(2)) / winDur;
            cnt  = gridN{k}(iy,ix);
            cur  = gridFR{k}(iy,ix);  if isnan(cur); cur = 0; end
            gridFR{k}(iy,ix) = (cur*cnt + fr) / (cnt+1);
            gridN{k}(iy,ix)  = cnt + 1;
        end
    end
end

% Gaussian smooth for continuous heatmap display
for k = 1:nU
    tmp = gridFR{k};  tmp(isnan(tmp)) = 0;
    gridFR{k} = imgaussfilt(tmp, SMOOTH_SIGMA);
end

% ── Tested target positions for overlay ───────────────────────────────────
tgt_xy = [];
for n = 1:numel(trials)
    for kt = 1:2
        t0 = trials(n).(sprintf('Target_%d_presented',kt));
        xy = trials(n).(sprintf('Target_%d_position', kt));
        if ~isnan(t0) && ~any(isnan(xy))
            tgt_xy = [tgt_xy; xy]; %#ok<AGROW>
        end
    end
end
if ~isempty(tgt_xy);  tgt_xy = unique(tgt_xy,'rows');  end

% ── Build Gaussian PSTH kernel ────────────────────────────────────────────
sig_bins = PSTH_SIGMA / BIN_MS;
kSz  = 2*ceil(3*sig_bins) + 1;
kern = exp(-0.5*((-floor(kSz/2):floor(kSz/2))/sig_bins).^2);
kern = kern / sum(kern);

% ── Compute PSTHs ──────────────────────────────────────────────────────────
[vT,vM,vS] = deal(cell(nU,1));   % visual-onset aligned
[gT,gM,gS] = deal(cell(nU,1));   % go-signal aligned
for k = 1:nU
    u = unitCols(k);
    [vT{k},vM{k},vS{k}] = buildPSTH(trials,chSel,u,'Target_1_presented',visWin,BIN_MS,kern);
    [gT{k},gM{k},gS{k}] = buildPSTH(trials,chSel,u,'Fixation_point_off', goWin, BIN_MS,kern);
end

% ── Rebuild axes when column count or selection changes ───────────────────
needRebuild = numel(axRF)~=nU || isempty(lastCh) || chSel~=lastCh ...
              || isempty(lastUnitSel) || ~isequal(unitSel,lastUnitSel);
if needRebuild
    delete(allchild(pRF));
    delete(allchild(pVis));
    delete(allchild(pGo));
    axRF  = gobjects(nU,1);
    axVis = gobjects(nU,1);
    axGo  = gobjects(nU,1);
    for k = 1:nU
        axRF(k)  = subplot(1,nU,k,'Parent',pRF);
        axVis(k) = subplot(1,nU,k,'Parent',pVis);
        axGo(k)  = subplot(1,nU,k,'Parent',pGo);
    end
    lastCh = chSel;  lastUnitSel = unitSel;
end

% ── Draw: Row 1 — RF heatmaps ─────────────────────────────────────────────
for k = 1:nU
    ax = axRF(k);  cla(ax);  hold(ax,'on');
    imagesc(ax, GRID_CTRS, GRID_CTRS, gridFR{k});
    axis(ax,[-20 20 -20 20]);  axis(ax,'equal');  axis(ax,'square');
    if ~isempty(tgt_xy)
        scatter(ax, tgt_xy(:,1), tgt_xy(:,2), 60, 'w','o','LineWidth',1.5);
    end
    scatter(ax, 0, 0, 30, FIX_COLOR,'filled');
    title(ax, sprintf('Ch %d  Unit %d', chSel, unitCols(k)-2), 'FontSize',10);
    colormap(ax,'parula');
    set(ax,'YDir','normal','XTick',[],'YTick',[]);
    box(ax,'on');
end

% ── Draw: Rows 2 & 3 — PSTHs ─────────────────────────────────────────────
clr = lines(max(nU,1));
for k = 1:nU
    lbl = sprintf('Ch %d  Unit %d', chSel, unitCols(k)-2);
    drawPSTH(axVis(k), vT{k}, vM{k}, vS{k}, clr(k,:), ...
             'Target onset (ms)', k==1, lbl);
    drawPSTH(axGo(k),  gT{k}, gM{k}, gS{k}, clr(k,:), ...
             'Go signal (ms)',    k==1, '');
end

drawnow limitrate
end

% ==========================================================================
function [t_c, fr_mn, fr_se] = buildPSTH(trials, chSel, u, tField, ...
                                           win_ms, bin_ms, kern)
% Bin spikes relative to alignment event, return smoothed mean ± SEM (sp/s).
t_edges = win_ms(1) : bin_ms : win_ms(2);
t_c     = t_edges(1:end-1) + bin_ms/2;
nBins   = numel(t_c);
allCnt  = [];

for n = 1:numel(trials)
    if ~ischar(trials(n).Trialoutcome) || ~contains(trials(n).Trialoutcome,'correct')
        continue
    end
    t0 = trials(n).(tField);
    sp = trials(n).spike_times;
    if isnan(t0) || isempty(sp) || chSel > size(sp,1) || u > size(sp,2)
        continue
    end
    ts_u = sp{chSel, u};
    if isempty(ts_u)
        cnt = zeros(1, nBins);
    else
        cnt = histcounts((ts_u - t0) * 1000, t_edges);
    end
    allCnt = [allCnt; cnt]; %#ok<AGROW>
end

if isempty(allCnt)
    fr_mn = zeros(1, nBins);
    fr_se = zeros(1, nBins);
    return
end

fr    = allCnt / (bin_ms / 1000);                    % sp/s per trial
fr_mn = conv(mean(fr, 1),                       kern, 'same');
fr_se = conv(std(fr,0,1) / sqrt(size(fr,1)),    kern, 'same');
end

% ==========================================================================
function drawPSTH(ax, t_c, fr_mn, fr_se, clr, xlbl, show_ylabel, ttl)
% Draw mean PSTH with ±1 SEM shaded region and a dashed zero-time line.
cla(ax);  hold(ax,'on');
fill(ax, [t_c, fliplr(t_c)], ...
         [fr_mn+fr_se, fliplr(fr_mn-fr_se)], ...
         clr, 'FaceAlpha',0.25, 'EdgeColor','none');
plot(ax, t_c, fr_mn, 'Color',clr, 'LineWidth',1.5);
hold on
xline(0,'LineStyle', '--', 'Color',[0.45 0.45 0.45], 'LineWidth',0.8);
%xline(ax, 0,'LineStyle', '--', 'Color',[0.45 0.45 0.45], 'LineWidth',0.8);
if show_ylabel;   ylabel(ax, 'FR (sp/s)');  end
if ~isempty(ttl); title(ax, ttl, 'FontSize',9);  end
xlabel(ax, xlbl);
set(ax, 'TickDir','out', 'FontSize',9, 'Box','off');
end
