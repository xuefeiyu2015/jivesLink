stop(T1); delete(T1);
 stop(T2); delete(T2);
 cbmex('trialconfig', 0);
 cbmex('close');
 global fhComments fhTrials;
 if ~isempty(fhComments) && fhComments > 0; fclose(fhComments); fhComments = []; end
 if ~isempty(fhTrials)   && fhTrials   > 0; fclose(fhTrials);   fhTrials   = []; end
 disp('Everything closed!');