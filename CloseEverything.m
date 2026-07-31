% CloseEverything.m — standalone cleanup for the Jives pipeline.
%
% Stops and deletes the acquisition timers, closes cbmex, and closes the
% streaming log files.
%
% Session data (`trials`, `spikeTrials`, `tsum`) is deliberately LEFT INTACT
% so it can be inspected after closing. jivesBROnline.m does `clear global`
% on start-up, so the next session begins clean regardless.
%
% NOTE: delete() on a timer whose TimerFcn is still executing BLOCKS
% indefinitely. T1 has a 0.25 s period and its callback can exceed that late
% in a session. (It now runs in 'fixedSpacing' mode, so an overrun no longer
% queues missed executions cumulatively, but a single in-flight callback can
% still be mid-execution here.) So: stop first, drain with a hard time bound,
% and only delete timers that have actually gone idle.

DRAIN_LIMIT = 3;   % seconds

Tlist = {};
if exist('T1','var') && isa(T1,'timer') && isvalid(T1); Tlist{end+1} = T1; end
if exist('T2','var') && isa(T2,'timer') && isvalid(T2); Tlist{end+1} = T2; end
% Also catch timers left behind by a previous session.
for tObj = timerfindall'
    if any(strcmp(tObj.Name, {'Jives_Acquire','Jives_Plot'})) && ...
            ~any(cellfun(@(x) isequal(x,tObj), Tlist))
        Tlist{end+1} = tObj; %#ok<SAGROW>
    end
end

% 1. Stop everything first so no further callbacks are queued.
for k = 1:numel(Tlist)
    if isvalid(Tlist{k}); stop(Tlist{k}); end
end

% 2. Bounded drain.
tDrain = tic;
busy = @() any(cellfun(@(t) isvalid(t) && strcmp(t.Running,'on'), Tlist));
while toc(tDrain) < DRAIN_LIMIT && busy()
    drawnow limitrate
end
stillBusy = busy();

% 3. Delete only the idle ones.
for k = 1:numel(Tlist)
    t = Tlist{k};
    if isvalid(t) && strcmp(t.Running,'off')
        delete(t);
    elseif isvalid(t)
        fprintf('[CloseEverything] "%s" still executing — left stopped, not deleted.\n', t.Name);
    end
end

% 4. Close cbmex only when nothing is in flight.
if stillBusy
    fprintf(['[CloseEverything] cbmex NOT closed — a callback is still running.\n' ...
             '                  Wait a few seconds and run this script again.\n']);
else
    try; cbmex('trialconfig', 0); catch; end
    try; cbmex('close');          catch; end
end

% 5. Close log files.
global fhComments fhTrials fhSpikes;
if ~isempty(fhComments) && fhComments > 0; fclose(fhComments); fhComments = []; end
if ~isempty(fhTrials)   && fhTrials   > 0; fclose(fhTrials);   fhTrials   = []; end
if ~isempty(fhSpikes)   && fhSpikes   > 0; fclose(fhSpikes);   fhSpikes   = []; end

if stillBusy
    disp('Partially closed — re-run once the warning above stops appearing.');
else
    disp('Everything closed!');
end
