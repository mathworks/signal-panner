classdef SignalPanner_demo < matlab.apps.App

    % Used to locate and load the app's XML configuration file
    properties (Access = public, Constant)
        AppConfigFilename = './SignalPanner_demo.xml'; % File path to the app configuration file containing component layout and settings
    end

    % Properties that correspond to app components
    properties (Access = public)
        SignalPannerDemoUIFigure        matlab.ui.Figure
        HelpLabel                       matlab.ui.control.Label
        StatusLabel                     matlab.ui.control.Label
        TitleLabel                      matlab.ui.control.Label
        FullViewButton                  matlab.ui.control.Button
        ZoomInButton                    matlab.ui.control.Button
        ZoomOutButton                   matlab.ui.control.Button
        SignalPanner                    SignalPanner
        UIAxes                          matlab.ui.control.UIAxes
    end

    % Copyright 2026 The MathWorks, Inc.

    properties (Access = private)
        AxesLimitsListener event.proplistener
        IsSynchronizing (1,1) logical = false
    end

    methods (Access = private)

        function axesLimitsChanged(app)
            if app.IsSynchronizing || isempty(app.SignalPanner) || ...
                    ~isvalid(app.SignalPanner)
                return
            end

            app.IsSynchronizing = true;
            cleanup = onCleanup(@()finishSynchronization(app));
            app.SignalPanner.ViewLimits = app.UIAxes.XLim;
            updateStatus(app, app.SignalPanner.ViewLimits, "axes");
            clear cleanup
        end

        function synchronizeAxes(app, limits)
            if app.IsSynchronizing
                return
            end

            app.IsSynchronizing = true;
            cleanup = onCleanup(@()finishSynchronization(app));
            app.UIAxes.XLim = limits;
            clear cleanup
        end

        function zoomView(app, scaleFactor)
            app.SignalPanner.zoomBy(scaleFactor);
            synchronizeAxes(app, app.SignalPanner.ViewLimits);
            updateStatus(app, app.SignalPanner.ViewLimits, "zoom");
        end

        function updateStatus(app, limits, interaction)
            app.StatusLabel.Text = sprintf( ...
                "%s  |  %.3f - %.3f s", interaction, limits(1), limits(2));
        end

        function finishSynchronization(app)
            app.IsSynchronizing = false;
        end
    end
    

    % Callbacks that handle component events
    methods

        % Code that executes after component creation
        function startupFcn(app)
            movegui(app.SignalPannerDemoUIFigure,"center")

            time = linspace(0, 12, 24000).';
            chirpSignal = sin(2*pi*(2.2*time + 0.19*time.^2));
            burstEnvelope = 0.25 + ...
                0.75 * exp(-0.5*((time - 7.2)/0.8).^2);
            burstSignal = burstEnvelope .* cos(2*pi*7.5*time);
            signals = [chirpSignal burstSignal];

            plot(app.UIAxes, time, signals, "LineWidth", 1);
            legend(app.UIAxes, ["Swept tone" "Burst"], ...
                "Location", "northeast");
            xlim(app.UIAxes, [1.5 4.0]);

            app.SignalPanner.setData(time, signals);
            app.SignalPanner.ViewLimits = [1.5 4.0];

            app.AxesLimitsListener = addlistener( ...
                app.UIAxes, "XLim", "PostSet", ...
                @(~,~)axesLimitsChanged(app));
            updateStatus(app, app.SignalPanner.ViewLimits, "ready");
        end

        % Callback function: SignalPanner
        function SignalPannerViewChanging(app, event)
            synchronizeAxes(app, event.ViewLimits);
            updateStatus(app, event.ViewLimits, event.Interaction);
        end

        % Button pushed function: ZoomOutButton
        function ZoomOutButtonPushed(app, event)
            zoomView(app, 2);
        end

        % Button pushed function: ZoomInButton
        function ZoomInButtonPushed(app, event)
            zoomView(app, 0.5);
        end

        % Button pushed function: FullViewButton
        function FullViewButtonPushed(app, event)
            app.SignalPanner.resetView();
            synchronizeAxes(app, app.SignalPanner.ViewLimits);
            updateStatus(app, app.SignalPanner.ViewLimits, "full view");
        end

        % Callback function: SignalPanner
        function SignalPannerViewChanged(app, event)
            synchronizeAxes(app, event.ViewLimits);
            updateStatus(app, event.ViewLimits, event.Interaction);
        end
    end

    % App creation
    methods (Access = public)

        % Construct app
        function app = SignalPanner_demo(varargin)
            app = app@matlab.apps.App(varargin{:});

            if nargout == 0
                clear app
            end
        end
    end
end