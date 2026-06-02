stop(T1); delete(T1);
 stop(T2); delete(T2);
 cbmex('trialconfig', 0);
 cbmex('close');
 disp('Everything closed!');