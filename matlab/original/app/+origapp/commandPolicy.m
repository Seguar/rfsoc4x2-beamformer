function [ok, reason] = commandPolicy(command, capabilities)
%COMMANDPOLICY Classify one board command for the RFSoC4x2 original app.
%
%   [ok, reason] = origapp.commandPolicy("dgain 1/2/3/4", caps)
%
% * ZCU216-only VSA_rfsoc_new commands (on-board DAC beamforming 'dacbf',
%   'dacbfcorr' and the burst request 'stream N') are always refused on the
%   RFSoC4x2: they need the ZCU216 overlay/notebook and are rejected by the
%   staged 4x2 legacy parser (board/legacy_server.py).
% * Other commands introduced by VSA_rfsoc_new ('dgain','again','diqphase',
%   'aiqphase') are refused unless the injected backend declares them in
%   capabilities().commands. No current 4x2 backend declares them; the
%   staged 4x2 parser accepts only fc/cal/phase/dphase/dataChan/dataStream/
%   da/dacPow.
% * Original-app commands keep their existing behaviour (queued, sent only
%   with cfg.allowBoardCommands); this function does not weaken that gate.
arguments
    command (1,1) string
    capabilities struct
end
verb = extractBefore(strtrim(command) + " ", " ");
zcu216Only = ["dacbf", "dacbfcorr", "stream"];
newVerbs = ["dgain", "again", "diqphase", "aiqphase", "phase"];
declared = string(capabilities.commands);
ok = true; reason = "";
if any(verb == zcu216Only)
    ok = false;
    reason = sprintf(['"%s" is a ZCU216 VSA_rfsoc_new command (on-board DAC BF / ' ...
        'stream burst); unsupported on RFSoC4x2.'], verb);
elseif any(verb == newVerbs) && ~any(declared == verb)
    ok = false;
    reason = sprintf(['"%s" is not declared by the backend capabilities ' ...
        '(declared: %s); not queued.'], verb, strjoin(declared, ','));
end
end
