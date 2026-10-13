classdef SignalPanner < matlab.ui.componentcontainer.ComponentContainer

    % Properties that correspond to underlying components
    properties (Access = private, Transient, NonCopyable)
        GridLayout    matlab.ui.container.GridLayout
        OverviewAxes  matlab.ui.control.UIAxes
    end

    % Copyright 2026 The MathWorks, Inc.

    properties
        %XData Monotonically increasing sample coordinates.
        XData (:,1) double = zeros(0,1)

        %YData Signal samples, with one signal per column.
        YData (:,:) double = zeros(0,0)

        %ViewLimits Visible x-axis interval. Use [NaN NaN] for full view.
        ViewLimits (1,2) double = [NaN NaN]

        %MinimumViewSpan Smallest selectable interval. Zero selects an
        %automatic minimum based on the data span.
        MinimumViewSpan (1,1) double = 0

        %MaxRenderedPoints Maximum overview vertices per signal.
        MaxRenderedPoints (1,1) double = 5000

        %SignalColors Colors cycled across signal columns.
        SignalColors (:,3) double = [
            0.0000 0.4470 0.7410
            0.8500 0.3250 0.0980
            0.9290 0.6940 0.1250
            0.4940 0.1840 0.5560
            0.4660 0.6740 0.1880
            0.3010 0.7450 0.9330
            0.6350 0.0780 0.1840]

        %SignalLineWidth Width of overview signal lines.
        SignalLineWidth (1,1) double = 0.75

        %ShadeColor Color applied outside the selected viewport.
        ShadeColor (1,3) double = [33 33 33] ./ 255

        %ShadeAlpha Opacity applied outside the selected viewport.
        ShadeAlpha (1,1) double = 0.30

        %ViewportColor Color of the selected viewport outline.
        ViewportColor (1,3) double = [33 33 33] ./ 255

        %ViewportLineWidth Width of the selected viewport outline.
        ViewportLineWidth (1,1) double = 1.25

        %ShowXAxis Whether to display x-axis tick labels.
        ShowXAxis (1,1) logical = false

        %InteractionsEnabled Whether mouse interactions are enabled.
        InteractionsEnabled (1,1) logical = true
    end

    properties (Dependent, SetAccess = private)
        %DataLimits Full x-axis interval represented by the data.
        DataLimits (1,2) double
    end

    events (HasCallbackProperty, NotifyAccess = private)
        %ViewChanging Fires repeatedly during an interaction.
        ViewChanging

        %ViewChanged Fires once when an interaction completes.
        ViewChanged
    end

    % Private component state
    properties (Access = private, Transient, NonCopyable)
        SignalLines matlab.graphics.chart.primitive.Line = ...
            matlab.graphics.chart.primitive.Line.empty
        LeftShade matlab.graphics.primitive.Patch
        RightShade matlab.graphics.primitive.Patch
        ViewportPatch matlab.graphics.primitive.Patch

        HostFigure matlab.ui.Figure
        FigureListeners event.listener = event.listener.empty

        DragMode (1,1) string = ""
        ActiveInteraction (1,1) string = ""
        PressX (1,1) double = NaN
        PressLimits (1,2) double = [NaN NaN]
        InteractionStartLimits (1,2) double = [NaN NaN]
        InteractionChanged (1,1) logical = false

        OriginalPointer (1,1) string = "arrow"
        PointerOwned (1,1) logical = false

        DataDirty (1,1) logical = true
        IsBatchUpdating (1,1) logical = false
        IsUpdating (1,1) logical = false
        IsSettingViewInternally (1,1) logical = false
        ViewChangedSinceUpdate (1,1) logical = false
        GraphicsReady (1,1) logical = false
        LastDataLimits (1,2) double = [NaN NaN]
    end

    % Public component API
    methods
        function value = get.DataLimits(comp)
            value = calculateDataLimits(comp);
        end

        function set.XData(comp, value)
            value = SignalPanner.validateXData(value);
            if ~comp.IsBatchUpdating && ~isempty(comp.YData) && ... %#ok<MCSUP>
                    ~SignalPanner.isCompatibleSize( ...
                    value, comp.YData) %#ok<MCSUP>
                error("SignalPanner:DataSizeMismatch", ...
                    "XData length must match a dimension of YData. " + ...
                    "Use setData to replace both arrays at once.");
            end
            comp.XData = value;
            comp.DataDirty = true; %#ok<MCSUP>
        end

        function set.YData(comp, value)
            value = SignalPanner.validateYData(value);
            if ~isempty(comp.XData) && ~isempty(value) %#ok<MCSUP>
                if size(value,1) == numel(comp.XData) %#ok<MCSUP>
                    % Samples already occupy rows.
                elseif size(value,2) == numel(comp.XData) %#ok<MCSUP>
                    value = value.';
                elseif ~comp.IsBatchUpdating %#ok<MCSUP>
                    error("SignalPanner:DataSizeMismatch", ...
                        "A dimension of YData must match the XData length. " + ...
                        "Use setData to replace both arrays at once.");
                end
            end
            comp.YData = value;
            comp.DataDirty = true; %#ok<MCSUP>
        end

        function set.ViewLimits(comp, value)
            value = SignalPanner.validateViewLimits(value);
            comp.ViewLimits = value;
            if ~comp.IsSettingViewInternally %#ok<MCSUP>
                comp.ViewChangedSinceUpdate = true; %#ok<MCSUP>
            end
        end

        function set.MinimumViewSpan(comp, value)
            validateattributes(value, {'numeric'}, ...
                {'real','finite','scalar','nonnegative'}, ...
                class(comp), "MinimumViewSpan");
            comp.MinimumViewSpan = double(value);
        end

        function set.MaxRenderedPoints(comp, value)
            validateattributes(value, {'numeric'}, ...
                {'real','finite','scalar','integer','>=',100}, ...
                class(comp), "MaxRenderedPoints");
            comp.MaxRenderedPoints = double(value);
            comp.DataDirty = true; %#ok<MCSUP>
        end

        function set.SignalColors(comp, value)
            comp.SignalColors = SignalPanner.validateColors( ...
                value, "SignalColors", false);
        end

        function set.SignalLineWidth(comp, value)
            validateattributes(value, {'numeric'}, ...
                {'real','finite','scalar','positive'}, ...
                class(comp), "SignalLineWidth");
            comp.SignalLineWidth = double(value);
        end

        function set.ShadeColor(comp, value)
            comp.ShadeColor = SignalPanner.validateColors( ...
                value, "ShadeColor", true);
        end

        function set.ShadeAlpha(comp, value)
            validateattributes(value, {'numeric'}, ...
                {'real','finite','scalar','>=',0,'<=',1}, ...
                class(comp), "ShadeAlpha");
            comp.ShadeAlpha = double(value);
        end

        function set.ViewportColor(comp, value)
            comp.ViewportColor = SignalPanner.validateColors( ...
                value, "ViewportColor", true);
        end

        function set.ViewportLineWidth(comp, value)
            validateattributes(value, {'numeric'}, ...
                {'real','finite','scalar','positive'}, ...
                class(comp), "ViewportLineWidth");
            comp.ViewportLineWidth = double(value);
        end

        function setData(comp, x, y)
            %SETDATA Replace XData and YData atomically.
            x = SignalPanner.validateXData(x);
            y = SignalPanner.validateYData(y);
            if ~isempty(x) && ~isempty(y)
                if size(y,1) == numel(x)
                    % Samples already occupy rows.
                elseif size(y,2) == numel(x)
                    y = y.';
                else
                    error("SignalPanner:DataSizeMismatch", ...
                        "A dimension of YData must match the XData length.");
                end
            end

            previousBatchState = comp.IsBatchUpdating;
            comp.IsBatchUpdating = true;
            cleanup = onCleanup(@()restoreBatchState(comp, previousBatchState));
            comp.XData = x;
            comp.YData = y;
            clear cleanup

            comp.DataDirty = true;
            update(comp);
        end

        function resetView(comp)
            %RESETVIEW Select the complete data interval.
            comp.ViewLimits = comp.DataLimits;
            update(comp);
        end

        function panBy(comp, delta)
            %PANBY Shift the viewport by an x-axis offset.
            validateattributes(delta, {'numeric'}, ...
                {'real','finite','scalar'}, class(comp), "delta");
            limits = constrainView(comp, comp.ViewLimits + double(delta));
            comp.ViewLimits = limits;
            update(comp);
        end

        function zoomBy(comp, scaleFactor, center)
            %ZOOMBY Scale the viewport about a coordinate.
            %   Values below one zoom in; values above one zoom out.
            validateattributes(scaleFactor, {'numeric'}, ...
                {'real','finite','scalar','positive'}, ...
                class(comp), "scaleFactor");
            if nargin < 3 || isempty(center)
                center = mean(comp.ViewLimits);
            end
            validateattributes(center, {'numeric'}, ...
                {'real','finite','scalar'}, class(comp), "center");

            limits = scaledView(comp, double(scaleFactor), double(center));
            comp.ViewLimits = limits;
            update(comp);
        end

        function delete(comp)
            releasePointer(comp);
            disconnectFigureListeners(comp);
        end
    end
    
    methods (Access = private)
        function limits = calculateDataLimits(comp)
            if ~isempty(comp.XData)
                limits = [comp.XData(1) comp.XData(end)];
            elseif ~isempty(comp.YData)
                limits = [1 size(comp.YData,1)];
            else
                limits = [0 1];
            end

            if limits(1) == limits(2)
                padding = max(0.5, 0.005 * abs(limits(1)));
                limits = limits + [-padding padding];
            end
        end

        function [x, y] = normalizedData(comp)
            y = comp.YData;
            if isempty(comp.XData)
                if isempty(y)
                    x = zeros(0,1);
                else
                    x = (1:size(y,1)).';
                end
            else
                x = comp.XData;
            end

            if isempty(y)
                y = zeros(numel(x), 0);
            elseif size(y,1) ~= numel(x)
                error("SignalPanner:DataSizeMismatch", ...
                    "The number of YData rows must match the XData length.");
            end
        end

        function updateSignalGraphics(comp)
            [x, y] = normalizedData(comp);
            channelCount = size(y,2);

            validLines = isgraphics(comp.SignalLines, "line");
            comp.SignalLines = comp.SignalLines(validLines);

            if numel(comp.SignalLines) > channelCount
                delete(comp.SignalLines(channelCount+1:end));
                comp.SignalLines = comp.SignalLines(1:channelCount);
            end

            while numel(comp.SignalLines) < channelCount
                comp.SignalLines(end+1) = plot(comp.OverviewAxes, NaN, NaN, ...
                    "HitTest", "off", ...
                    "PickableParts", "none", ...
                    "HandleVisibility", "off", ...
                    "Tag", "SignalPannerSignal");
            end

            for channel = 1:channelCount
                [displayX, displayY] = SignalPanner.minMaxEnvelope( ...
                    x, y(:,channel), comp.MaxRenderedPoints);
                comp.SignalLines(channel).XData = displayX;
                comp.SignalLines(channel).YData = displayY;
            end

            finiteY = y(isfinite(y));
            if isempty(finiteY)
                yLimits = [-1 1];
            else
                yMinimum = min(finiteY);
                yMaximum = max(finiteY);
                if yMinimum == yMaximum
                    padding = max(1, 0.05 * abs(yMinimum));
                else
                    padding = 0.08 * (yMaximum - yMinimum);
                end
                yLimits = [yMinimum-padding yMaximum+padding];
            end
            comp.OverviewAxes.YLim = yLimits;
        end

        function updateSignalStyles(comp)
            colorCount = size(comp.SignalColors,1);
            for channel = 1:numel(comp.SignalLines)
                colorIndex = mod(channel-1, colorCount) + 1;
                comp.SignalLines(channel).Color = ...
                    comp.SignalColors(colorIndex,:);
                comp.SignalLines(channel).LineWidth = comp.SignalLineWidth;
            end

            comp.LeftShade.FaceColor = comp.ShadeColor;
            comp.LeftShade.FaceAlpha = comp.ShadeAlpha;
            comp.RightShade.FaceColor = comp.ShadeColor;
            comp.RightShade.FaceAlpha = comp.ShadeAlpha;
            comp.ViewportPatch.EdgeColor = comp.ViewportColor;
            comp.ViewportPatch.LineWidth = comp.ViewportLineWidth;
        end

        function updateRegionGraphics(comp)
            if ~comp.GraphicsReady || ~isvalid(comp.ViewportPatch)
                return
            end

            dataLimits = comp.DataLimits;
            viewLimits = constrainView(comp, comp.ViewLimits);
            yLimits = comp.OverviewAxes.YLim;
            yVertices = [yLimits(1) yLimits(1) yLimits(2) yLimits(2)];

            comp.LeftShade.XData = [
                dataLimits(1) viewLimits(1) ...
                viewLimits(1) dataLimits(1)];
            comp.LeftShade.YData = yVertices;
            comp.RightShade.XData = [
                viewLimits(2) dataLimits(2) ...
                dataLimits(2) viewLimits(2)];
            comp.RightShade.YData = yVertices;
            comp.ViewportPatch.XData = [
                viewLimits(1) viewLimits(2) ...
                viewLimits(2) viewLimits(1)];
            comp.ViewportPatch.YData = yVertices;

            tolerance = 32 * eps(max(1, max(abs(dataLimits))));
            comp.LeftShade.Visible = SignalPanner.onOff( ...
                viewLimits(1) > dataLimits(1) + tolerance);
            comp.RightShade.Visible = SignalPanner.onOff( ...
                viewLimits(2) < dataLimits(2) - tolerance);

            uistack(comp.LeftShade, "top");
            uistack(comp.RightShade, "top");
            uistack(comp.ViewportPatch, "top");
        end

        function limits = constrainView(comp, requestedLimits)
            dataLimits = comp.DataLimits;
            if numel(requestedLimits) ~= 2 || any(~isfinite(requestedLimits))
                limits = dataLimits;
                return
            end

            dataSpan = diff(dataLimits);
            requestedSpan = diff(requestedLimits);
            minimumSpan = effectiveMinimumSpan(comp);
            viewSpan = min(dataSpan, max(requestedSpan, minimumSpan));

            left = min(max(requestedLimits(1), dataLimits(1)), ...
                dataLimits(2) - viewSpan);
            limits = [left left + viewSpan];

            if limits(2) > dataLimits(2)
                limits = dataLimits(2) + [-viewSpan 0];
            end
        end

        function span = effectiveMinimumSpan(comp)
            dataLimits = comp.DataLimits;
            dataSpan = diff(dataLimits);
            automaticSpan = max(dataSpan * 1e-6, ...
                32 * eps(max(1, max(abs(dataLimits)))));
            if comp.MinimumViewSpan == 0
                span = automaticSpan;
            else
                span = min(dataSpan, max(comp.MinimumViewSpan, automaticSpan));
            end
        end

        function limits = scaledView(comp, scaleFactor, center)
            dataLimits = comp.DataLimits;
            currentLimits = constrainView(comp, comp.ViewLimits);
            currentSpan = diff(currentLimits);
            newSpan = min(diff(dataLimits), ...
                max(currentSpan * scaleFactor, effectiveMinimumSpan(comp)));

            relativeCenter = (center - currentLimits(1)) / currentSpan;
            relativeCenter = min(max(relativeCenter, 0), 1);
            proposedLeft = center - relativeCenter * newSpan;
            limits = constrainView(comp, ...
                [proposedLeft proposedLeft + newSpan]);
        end

        function setViewInternally(comp, limits)
            if SignalPanner.limitsEqual(comp.ViewLimits, limits)
                return
            end
            previousState = comp.IsSettingViewInternally;
            comp.IsSettingViewInternally = true;
            cleanup = onCleanup(@()restoreInternalViewState( ...
                comp, previousState));
            comp.ViewLimits = limits;
            clear cleanup
            comp.IsSettingViewInternally = previousState;
        end

        function changed = applyInteractiveView(comp, limits, interaction)
            limits = constrainView(comp, limits);
            previousLimits = comp.ViewLimits;
            changed = ~SignalPanner.limitsEqual(previousLimits, limits);
            if ~changed
                return
            end

            comp.ViewLimits = limits;
            updateRegionGraphics(comp);
            eventData = SignalPannerEventData( ...
                limits, previousLimits, interaction);
            notify(comp, "ViewChanging", eventData);
        end

        function connectFigureListeners(comp)
            figureHandle = ancestor(comp, "figure");
            alreadyConnected = ~isempty(comp.HostFigure) && ...
                isvalid(comp.HostFigure) && ...
                isequal(figureHandle, comp.HostFigure) && ...
                ~isempty(comp.FigureListeners) && ...
                all(isvalid(comp.FigureListeners));
            if alreadyConnected
                return
            end

            disconnectFigureListeners(comp);
            if isempty(figureHandle) || ~isvalid(figureHandle)
                return
            end

            comp.HostFigure = figureHandle;
            comp.FigureListeners(end+1) = addlistener(figureHandle, ...
                "WindowMousePress", @(src,evt)onMousePress(comp, src, evt));
            comp.FigureListeners(end+1) = addlistener(figureHandle, ...
                "WindowMouseMotion", @(src,evt)onMouseMotion(comp, src, evt));
            comp.FigureListeners(end+1) = addlistener(figureHandle, ...
                "WindowMouseRelease", @(src,evt)onMouseRelease(comp, src, evt));
            comp.FigureListeners(end+1) = addlistener(figureHandle, ...
                "WindowScrollWheel", @(src,evt)onScrollWheel(comp, src, evt));
        end

        function disconnectFigureListeners(comp)
            if ~isempty(comp.FigureListeners)
                validListeners = isvalid(comp.FigureListeners);
                delete(comp.FigureListeners(validListeners));
                comp.FigureListeners = event.listener.empty;
            end
            comp.HostFigure = matlab.ui.Figure.empty;
        end

        function onMousePress(comp, ~, eventData)
            if ~comp.InteractionsEnabled || ~eventIsInsideAxes(comp, eventData)
                return
            end
            if ~isempty(comp.HostFigure) && ...
                    ~strcmp(comp.HostFigure.SelectionType, "normal")
                return
            end

            x = currentX(comp, eventData);
            if ~isfinite(x)
                return
            end

            originalLimits = constrainView(comp, comp.ViewLimits);
            mode = hitMode(comp, x);
            comp.InteractionStartLimits = originalLimits;
            comp.InteractionChanged = false;

            if mode == "recenter"
                span = diff(originalLimits);
                recentered = constrainView(comp, ...
                    [x-span/2 x+span/2]);
                comp.InteractionChanged = applyInteractiveView( ...
                    comp, recentered, "recenter");
                comp.PressLimits = recentered;
                comp.DragMode = "pan";
                comp.ActiveInteraction = "recenter";
            else
                comp.PressLimits = originalLimits;
                comp.DragMode = mode;
                comp.ActiveInteraction = mode;
            end
            comp.PressX = x;
            setPointerForMode(comp, comp.DragMode);
        end

        function onMouseMotion(comp, ~, eventData)
            if ~comp.InteractionsEnabled
                releasePointer(comp);
                return
            end

            if comp.DragMode ~= ""
                x = currentX(comp, eventData);
                if ~isfinite(x)
                    return
                end
                delta = x - comp.PressX;
                minimumSpan = effectiveMinimumSpan(comp);

                switch comp.DragMode
                    case "pan"
                        proposedLimits = comp.PressLimits + delta;
                    case "resize-left"
                        newLeft = min(x, comp.PressLimits(2)-minimumSpan);
                        proposedLimits = [newLeft comp.PressLimits(2)];
                    case "resize-right"
                        newRight = max(x, comp.PressLimits(1)+minimumSpan);
                        proposedLimits = [comp.PressLimits(1) newRight];
                    otherwise
                        return
                end

                changed = applyInteractiveView( ...
                    comp, proposedLimits, comp.ActiveInteraction);
                comp.InteractionChanged = comp.InteractionChanged || changed;
                return
            end

            if eventIsInsideAxes(comp, eventData)
                setPointerForMode(comp, ...
                    hitMode(comp, currentX(comp, eventData)));
            else
                releasePointer(comp);
            end
        end

        function onMouseRelease(comp, ~, eventData)
            if comp.DragMode == ""
                return
            end

            if comp.InteractionChanged
                changedEvent = SignalPannerEventData( ...
                    comp.ViewLimits, ...
                    comp.InteractionStartLimits, ...
                    comp.ActiveInteraction);
                notify(comp, "ViewChanged", changedEvent);
            end

            comp.DragMode = "";
            comp.ActiveInteraction = "";
            comp.PressX = NaN;
            comp.PressLimits = [NaN NaN];
            comp.InteractionStartLimits = [NaN NaN];
            comp.InteractionChanged = false;

            if eventIsInsideAxes(comp, eventData)
                setPointerForMode(comp, ...
                    hitMode(comp, currentX(comp, eventData)));
            else
                releasePointer(comp);
            end
        end

        function onScrollWheel(comp, ~, eventData)
            if ~comp.InteractionsEnabled || comp.DragMode ~= "" || ...
                    ~eventIsInsideAxes(comp, eventData)
                return
            end

            try
                scrollCount = eventData.VerticalScrollCount;
            catch
                return
            end
            if scrollCount == 0
                return
            end

            center = currentX(comp, eventData);
            previousLimits = comp.ViewLimits;
            scaleFactor = 1.20 ^ double(scrollCount);
            proposedLimits = scaledView(comp, scaleFactor, center);
            changed = applyInteractiveView(comp, proposedLimits, "zoom");
            if changed
                changedEvent = SignalPannerEventData( ...
                    comp.ViewLimits, previousLimits, "zoom");
                notify(comp, "ViewChanged", changedEvent);
            end
        end

        function tf = eventIsInsideAxes(comp, eventData)
            tf = false;
            if isempty(comp.HostFigure) || ~isvalid(comp.HostFigure) || ...
                    isempty(comp.OverviewAxes) || ~isvalid(comp.OverviewAxes)
                return
            end

            if isprop(eventData, "HitObject")
                hitObject = eventData.HitObject;
            else
                try
                    hitObject = hittest(comp.HostFigure);
                catch
                    return
                end
            end
            if isempty(hitObject) || ~isgraphics(hitObject)
                return
            end

            if isequal(hitObject, comp.OverviewAxes)
                tf = true;
                return
            end
            try
                tf = isequal(ancestor(hitObject, "axes"), comp.OverviewAxes);
            catch
                tf = false;
            end
        end

        function x = currentX(comp, eventData)
            if nargin > 1 && isprop(eventData, "IntersectionPoint")
                point = eventData.IntersectionPoint;
                if ~isempty(point) && isfinite(point(1))
                    x = point(1);
                    return
                end
            end
            try
                point = comp.OverviewAxes.CurrentPoint;
                x = point(1,1);
            catch
                x = NaN;
            end
        end

        function mode = hitMode(comp, x)
            viewLimits = constrainView(comp, comp.ViewLimits);
            tolerance = edgeHitTolerance(comp);
            leftDistance = abs(x - viewLimits(1));
            rightDistance = abs(x - viewLimits(2));

            nearLeft = leftDistance <= tolerance;
            nearRight = rightDistance <= tolerance;
            if nearLeft && (~nearRight || leftDistance <= rightDistance)
                mode = "resize-left";
            elseif nearRight
                mode = "resize-right";
            elseif x > viewLimits(1) && x < viewLimits(2)
                mode = "pan";
            else
                mode = "recenter";
            end
        end

        function tolerance = edgeHitTolerance(comp)
            dataSpan = diff(comp.DataLimits);
            pixelWidth = 600;
            try
                pixelPosition = getpixelposition(comp.OverviewAxes, true);
                pixelWidth = max(pixelPosition(3), 100);
            catch
                % Use a representative width while layout is initializing.
            end
            tolerance = max(0.003 * dataSpan, 7 * dataSpan / pixelWidth);
        end

        function setPointerForMode(comp, mode)
            if isempty(comp.HostFigure) || ~isvalid(comp.HostFigure)
                return
            end
            switch mode
                case "resize-left"
                    pointer = "left";
                case "resize-right"
                    pointer = "right";
                case "pan"
                    pointer = "fleur";
                otherwise
                    pointer = "hand";
            end

            if ~comp.PointerOwned
                comp.OriginalPointer = string(comp.HostFigure.Pointer);
                comp.PointerOwned = true;
            end
            comp.HostFigure.Pointer = char(pointer);
        end

        function releasePointer(comp)
            if comp.PointerOwned && ~isempty(comp.HostFigure) && ...
                    isvalid(comp.HostFigure)
                comp.HostFigure.Pointer = char(comp.OriginalPointer);
            end
            comp.PointerOwned = false;
        end

        function restoreBatchState(comp, previousState)
            comp.IsBatchUpdating = previousState;
        end

        function restoreInternalViewState(comp, previousState)
            comp.IsSettingViewInternally = previousState;
        end

        function finishUpdate(comp)
            comp.IsUpdating = false;
        end
    end

     methods (Static, Access = private)
        function value = validateXData(value)
            validateattributes(value, {'numeric'}, ...
                {'real','finite','vector'}, "SignalPanner", "XData");
            value = double(value(:));
            if numel(value) > 1 && any(diff(value) <= 0)
                error("SignalPanner:XDataNotIncreasing", ...
                    "XData must be strictly increasing.");
            end
        end

        function value = validateYData(value)
            validateattributes(value, {'numeric'}, ...
                {'real','2d'}, "SignalPanner", "YData");
            if any(isinf(value), "all")
                error("SignalPanner:YDataInfinite", ...
                    "YData can contain finite values or NaN, but not Inf.");
            end
            value = double(value);
            if isvector(value) && ~isempty(value)
                value = value(:);
            end
        end

        function value = validateViewLimits(value)
            validateattributes(value, {'numeric'}, ...
                {'real','numel',2}, "SignalPanner", "ViewLimits");
            value = double(reshape(value, 1, 2));
            if all(isnan(value))
                return
            end
            if any(~isfinite(value)) || value(1) >= value(2)
                error("SignalPanner:InvalidViewLimits", ...
                    "ViewLimits must contain two increasing finite " + ...
                    "values or [NaN NaN].");
            end
        end

        function colors = validateColors( ...
                value, propertyName, requireSingleColor)
            validateattributes(value, {'numeric'}, ...
                {'real','finite','2d','nonempty'}, ...
                "SignalPanner", propertyName);
            if size(value,2) ~= 3 || ...
                    any(value < 0, "all") || any(value > 1, "all")
                error("SignalPanner:InvalidColor", ...
                    "%s must contain RGB rows with values in " + ...
                    "the range [0, 1].", propertyName);
            end
            if requireSingleColor && size(value,1) ~= 1
                error("SignalPanner:InvalidColor", ...
                    "%s must be a single RGB triplet.", propertyName);
            end
            colors = double(value);
        end

        function tf = isCompatibleSize(x, y)
            tf = isempty(x) || isempty(y) || ...
                size(y,1) == numel(x) || size(y,2) == numel(x);
        end

        function tf = limitsEqual(first, second)
            if numel(first) ~= 2 || numel(second) ~= 2
                tf = false;
                return
            end
            if all(isnan(first)) && all(isnan(second))
                tf = true;
                return
            end
            if any(~isfinite(first)) || any(~isfinite(second))
                tf = false;
                return
            end
            tolerance = 64 * eps(max([1 abs(first) abs(second)]));
            tf = all(abs(first - second) <= tolerance);
        end

        function state = onOff(tf)
            if tf
                state = "on";
            else
                state = "off";
            end
        end

        function [displayX, displayY] = minMaxEnvelope( ...
                x, y, maximumPoints)
            sampleCount = numel(x);
            if sampleCount <= maximumPoints || sampleCount < 3
                displayX = x;
                displayY = y;
                return
            end

            binCount = max(1, floor(maximumPoints / 2));
            edges = round(linspace(1, sampleCount + 1, binCount + 1));
            displayX = NaN(2 * binCount, 1);
            displayY = NaN(2 * binCount, 1);
            outputIndex = 0;

            for bin = 1:binCount
                firstIndex = edges(bin);
                lastIndex = max(firstIndex, edges(bin+1) - 1);
                indices = firstIndex:lastIndex;
                values = y(indices);
                finiteMask = isfinite(values);

                if ~any(finiteMask)
                    outputIndex = outputIndex + 1;
                    displayX(outputIndex) = x(firstIndex);
                    displayY(outputIndex) = NaN;
                    continue
                end

                finiteIndices = indices(finiteMask);
                finiteValues = values(finiteMask);
                [minimumValue, minimumOffset] = min(finiteValues);
                [maximumValue, maximumOffset] = max(finiteValues);
                extremaIndices = [
                    finiteIndices(minimumOffset) ...
                    finiteIndices(maximumOffset)];
                extremaValues = [minimumValue maximumValue];
                [extremaIndices, order] = sort(extremaIndices);
                extremaValues = extremaValues(order);

                outputIndex = outputIndex + 1;
                displayX(outputIndex) = x(extremaIndices(1));
                displayY(outputIndex) = extremaValues(1);
                if extremaIndices(2) ~= extremaIndices(1)
                    outputIndex = outputIndex + 1;
                    displayX(outputIndex) = x(extremaIndices(2));
                    displayY(outputIndex) = extremaValues(2);
                end
            end

            displayX = displayX(1:outputIndex);
            displayY = displayY(1:outputIndex);
        end
     end

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function postSetupFcn(comp)
            comp.OverviewAxes.Interactions = [];
            disableDefaultInteractivity(comp.OverviewAxes);
            hold(comp.OverviewAxes, "on");

            yVertices = [-1 -1 1 1];
            comp.LeftShade = patch(comp.OverviewAxes, ...
                [0 0 0 0], yVertices, comp.ShadeColor, ...
                "FaceAlpha", comp.ShadeAlpha, ...
                "EdgeColor", "none", ...
                "HitTest", "on", ...
                "PickableParts", "all", ...
                "Tag", "SignalPannerLeftShade");
            comp.RightShade = patch(comp.OverviewAxes, ...
                [1 1 1 1], yVertices, comp.ShadeColor, ...
                "FaceAlpha", comp.ShadeAlpha, ...
                "EdgeColor", "none", ...
                "HitTest", "on", ...
                "PickableParts", "all", ...
                "Tag", "SignalPannerRightShade");
            comp.ViewportPatch = patch(comp.OverviewAxes, ...
                [0 1 1 0], yVertices, comp.ViewportColor, ...
                "FaceColor", "none", ...
                "EdgeColor", comp.ViewportColor, ...
                "LineWidth", comp.ViewportLineWidth, ...
                "HitTest", "off", ...
                "PickableParts", "none", ...
                "Tag", "SignalPannerViewport");

            comp.GraphicsReady = true;
            connectFigureListeners(comp);
        end
    end

    methods (Access = protected)
        
        % Code that executes when the value of a property is changed
        function update(comp)
            if comp.IsBatchUpdating || comp.IsUpdating || ...
                    ~comp.GraphicsReady || ...
                    isempty(comp.OverviewAxes) || ...
                    ~isvalid(comp.OverviewAxes)
                return
            end

            comp.IsUpdating = true;
            cleanup = onCleanup(@()finishUpdate(comp));

            connectFigureListeners(comp);

            dataLimits = comp.DataLimits;
            dataChanged = comp.DataDirty || ...
                any(~isfinite(comp.LastDataLimits)) || ...
                ~SignalPanner.limitsEqual(dataLimits, comp.LastDataLimits);

            if all(isnan(comp.ViewLimits))
                desiredLimits = dataLimits;
            elseif dataChanged && ~comp.ViewChangedSinceUpdate && ...
                    all(isfinite(comp.LastDataLimits)) && ...
                    SignalPanner.limitsEqual( ...
                    comp.ViewLimits, comp.LastDataLimits)
                desiredLimits = dataLimits;
            else
                desiredLimits = constrainView(comp, comp.ViewLimits);
            end
            setViewInternally(comp, desiredLimits);

            comp.GridLayout.BackgroundColor = comp.BackgroundColor;
            comp.OverviewAxes.Color = comp.BackgroundColor;
            comp.OverviewAxes.XLim = dataLimits;

            if comp.ShowXAxis
                comp.OverviewAxes.XTickMode = "auto";
                comp.OverviewAxes.XTickLabelMode = "auto";
                comp.OverviewAxes.XColor = [0.15 0.15 0.15];
            else
                comp.OverviewAxes.XTick = [];
                comp.OverviewAxes.XColor = [0.55 0.55 0.55];
            end
            comp.OverviewAxes.YTick = [];
            comp.OverviewAxes.YColor = [0.55 0.55 0.55];

            if comp.DataDirty
                updateSignalGraphics(comp);
                comp.DataDirty = false;
            end
            updateSignalStyles(comp);
            updateRegionGraphics(comp);

            comp.LastDataLimits = dataLimits;
            comp.ViewChangedSinceUpdate = false;
            clear cleanup
            comp.IsUpdating = false;
        end

        % Create the underlying components
        function setup(comp)

            comp.Position = [1 1 600 80];
            comp.BackgroundColor = [1 1 1];

            % Create GridLayout
            comp.GridLayout = uigridlayout(comp);
            comp.GridLayout.ColumnWidth = {'1x'};
            comp.GridLayout.RowHeight = {'1x'};
            comp.GridLayout.ColumnSpacing = 0;
            comp.GridLayout.RowSpacing = 0;
            comp.GridLayout.Padding = [0 0 0 0];

            % Create OverviewAxes
            comp.OverviewAxes = uiaxes(comp.GridLayout);
            comp.OverviewAxes.Toolbar.Visible = 'off';
            comp.OverviewAxes.XTick = [];
            comp.OverviewAxes.YTick = [];
            comp.OverviewAxes.Box = 'on';
            comp.OverviewAxes.Layout.Row = 1;
            comp.OverviewAxes.Layout.Column = 1;
            
            % Execute the startup function
            postSetupFcn(comp)
        end
    end
end