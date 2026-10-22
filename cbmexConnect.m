function cbmexConnect(commentBuf)
% cbmexConnect  Open cbmex and confirm Blackrock Central is answering.
%
%   cbmexConnect(commentBuf) closes any half-open cbmex socket, opens a new
%   one, pings the NSP with cbmex('time') and configures the trial buffers
%   with a comment buffer of commentBuf entries.
%
%   cbmex('open') alone is not a reliable readiness test: the ping is a real
%   round-trip, so it fails when Central is closed or the NSP is not running.
%   On any failure cbmex is closed again and an error with identifier
%   'jives:centralNotReady' is thrown; its message tells the user to open
%   Central first, so callers can show it directly in a dialog.

% Drop any half-open socket left by a previous session. Without this,
% cbmex('open') sits on a connect timeout after an unclean shutdown.
try; cbmex('close'); catch; end
try
    cbmex('open');
    cbmex('time');
    cbmex('trialconfig', 1, 'double', 'absolute', 'comment', commentBuf);
catch ME
    try; cbmex('close'); catch; end
    error('jives:centralNotReady', '%s', sprintf([ ...
        'Cannot reach Blackrock Central.\n\n' ...
        'Please open Central and make sure the NSP is connected and ' ...
        'running, then start again.\n\ncbmex: %s'], ME.message));
end
end
