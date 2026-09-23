classdef SignalPannerEventData < event.EventData
    %SIGNALPANNEREVENTDATA Data supplied by SignalPanner view callbacks.

    % Copyright 2026 The MathWorks, Inc.

    properties (SetAccess = immutable)
        %ViewLimits Current selected interval.
        ViewLimits (1,2) double

        %PreviousViewLimits Selected interval before this change.
        PreviousViewLimits (1,2) double

        %Interaction Interaction that caused the change.
        %   Values are "pan", "resize-left", "resize-right", "recenter",
        %   or "zoom".
        Interaction (1,1) string
    end

    methods
        function eventData = SignalPannerEventData( ...
                viewLimits, previousViewLimits, interaction)
            eventData.ViewLimits = viewLimits;
            eventData.PreviousViewLimits = previousViewLimits;
            eventData.Interaction = string(interaction);
        end
    end
end
