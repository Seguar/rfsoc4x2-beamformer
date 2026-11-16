function spec = uiExtensionSpec()
%UIEXTENSIONSPEC Explicit component-model extension of the 119-component
% VSA_rfsoc_refactor model: one appended tab "New" holding the VSA_rfsoc_new
% controls ported to the RFSoC4x2 app. CodeNames and callback names follow
% VSA_rfsoc_new where that app has the control; DACportDropDown, DACfileButton,
% PortStatusLabel and NewTab are new. Existing components are not changed.
%
% Each row: ctor (design-time constructor of the parent handle), CodeName,
% parent CodeName, property name/value pairs, callback property, callback.
% build_mlapp_ext creates the components in this order, generates their
% code with App Designer's ComponentCodeGenerator and binds callbacks by
% name; verify_mlapp_ext checks every row after a fresh-process reload.
items = {'DAC gain','DAC phase','DAC I phase','ADC gain','ADC phase','ADC I phase','DAC phase corr'};
R = {
 @(p) uitab(p), 'NewTab', 'TabGroup', {'Title','New'}, '', ''
 @(p) uicheckbox(p), 'IQCompCheckBox', 'NewTab', {'Text','IQ comp','Position',[10 640 75 22]}, 'ValueChangedFcn', 'IQCompCheckBoxValueChanged'
 @(p) uicheckbox(p), 'AdaptiveIQcompCheckBox', 'NewTab', {'Text','Adaptive IQ comp','Position',[90 640 120 22]}, 'ValueChangedFcn', 'AdaptiveIQcompCheckBoxValueChanged'
 @(p) uilabel(p), 'LsizeEditFieldLabel', 'NewTab', {'HorizontalAlignment','right','Position',[5 612 40 22],'Text','L size'}, '', ''
 @(p) uieditfield(p,'numeric'), 'LsizeEditField', 'NewTab', {'Limits',[1 50],'RoundFractionalValues','on','Position',[50 612 40 22],'Value',4}, 'ValueChangedFcn', 'LsizeEditFieldValueChanged'
 @(p) uilabel(p), 'MUstepEditFieldLabel', 'NewTab', {'HorizontalAlignment','right','Position',[95 612 50 22],'Text','MU step'}, '', ''
 @(p) uieditfield(p,'numeric'), 'MUstepEditField', 'NewTab', {'Limits',[1e-31 1],'Position',[150 612 60 22],'Value',1e-16}, 'ValueChangedFcn', 'MUstepEditFieldValueChanged'
 @(p) uicheckbox(p), 'PhasecompCheckBox', 'NewTab', {'Text','Phase/power comp','Position',[10 584 125 22]}, 'ValueChangedFcn', 'PhasecompCheckBoxValueChanged'
 @(p) uicheckbox(p), 'CouplingcompCheckBox', 'NewTab', {'Text','Coupling comp','Position',[10 558 110 22]}, 'ValueChangedFcn', 'CouplingcompCheckBoxValueChanged'
 @(p) uicheckbox(p), 'EVMCheckBox', 'NewTab', {'Text','EVM','Position',[10 532 50 22]}, 'ValueChangedFcn', 'EVMCheckBoxValueChanged'
 @(p) uicheckbox(p), 'MirrorCheckBox_3', 'NewTab', {'Text','Mirror plot','Position',[90 532 85 22]}, 'ValueChangedFcn', 'MirrorCheckBox_3ValueChanged'
 @(p) uibutton(p,'push'), 'PrintphasemissmatchButton', 'NewTab', {'Position',[10 502 200 23],'Text','Print phase mismatch'}, 'ButtonPushedFcn', 'PrintphasemissmatchButtonPushed'
 @(p) uilabel(p), 'DACBFmodeListBoxLabel', 'NewTab', {'Position',[10 472 95 22],'Text','DAC BF mode'}, '', ''
 @(p) uilistbox(p), 'DACBFmodeListBox', 'NewTab', {'Items',{'GUI','Random','Scaning','Rescaning','Tracking','Retracking','Off'},'Position',[10 352 95 118],'Value','Off'}, 'ValueChangedFcn', 'DACBFmodeListBoxValueChanged'
 @(p) uilabel(p), 'RFSOCBFmodeListBoxLabel', 'NewTab', {'Position',[115 472 95 22],'Text','RFSoC BF mode'}, '', ''
 @(p) uilistbox(p), 'RFSOCBFmodeListBox', 'NewTab', {'Items',{'Tracking','Retracking','Off'},'Position',[115 412 95 58],'Value','Off'}, 'ValueChangedFcn', 'RFSOCBFmodeListBoxValueChanged'
 @(p) uilabel(p), 'BurstLenSpinnerLabel', 'NewTab', {'HorizontalAlignment','right','Position',[112 382 55 22],'Text','Burst len'}, '', ''
 @(p) uispinner(p), 'BurstLenSpinner', 'NewTab', {'Limits',[1 100],'RoundFractionalValues','on','Position',[170 382 40 22],'Value',1}, 'ValueChangedFcn', 'BurstLenSpinnerValueChanged'
 @(p) uilabel(p), 'ChannelcontrolDropDownLabel', 'NewTab', {'Position',[10 320 90 22],'Text','Channel control'}, '', ''
 @(p) uidropdown(p), 'ChannelcontrolDropDown', 'NewTab', {'Items',items,'Position',[100 320 110 22],'Value','DAC phase'}, 'ValueChangedFcn', 'ChannelcontrolDropDownValueChanged'
 @(p) uilabel(p), 'Ch1SpinnerLabel', 'NewTab', {'HorizontalAlignment','right','Position',[5 290 30 22],'Text','Ch1'}, '', ''
 @(p) uispinner(p), 'Ch1Spinner', 'NewTab', {'Limits',[-179 179],'Position',[40 290 65 22]}, 'ValueChangedFcn', 'Ch1SpinnerValueChanged'
 @(p) uilabel(p), 'Ch2SpinnerLabel', 'NewTab', {'HorizontalAlignment','right','Position',[105 290 30 22],'Text','Ch2'}, '', ''
 @(p) uispinner(p), 'Ch2Spinner', 'NewTab', {'Limits',[-179 179],'Position',[140 290 70 22]}, 'ValueChangedFcn', 'Ch2SpinnerValueChanged'
 @(p) uilabel(p), 'Ch3SpinnerLabel', 'NewTab', {'HorizontalAlignment','right','Position',[5 262 30 22],'Text','Ch3'}, '', ''
 @(p) uispinner(p), 'Ch3Spinner', 'NewTab', {'Limits',[-179 179],'Position',[40 262 65 22]}, 'ValueChangedFcn', 'Ch3SpinnerValueChanged'
 @(p) uilabel(p), 'Ch4SpinnerLabel', 'NewTab', {'HorizontalAlignment','right','Position',[105 262 30 22],'Text','Ch4'}, '', ''
 @(p) uispinner(p), 'Ch4Spinner', 'NewTab', {'Limits',[-179 179],'Position',[140 262 70 22]}, 'ValueChangedFcn', 'Ch4SpinnerValueChanged'
 @(p) uilabel(p), 'DACportDropDownLabel', 'NewTab', {'Position',[10 222 60 22],'Text','DAC port'}, '', ''
 @(p) uidropdown(p), 'DACportDropDown', 'NewTab', {'Items',{'DAC_B (dac0)','DAC_A (dac1)'},'Position',[75 222 135 22],'Value','DAC_B (dac0)'}, '', ''
 @(p) uibutton(p,'push'), 'DACfileButton', 'NewTab', {'Position',[10 192 200 23],'Text','Prepare DAC file'}, 'ButtonPushedFcn', 'DACfileButtonPushed'
 @(p) uilabel(p), 'PortStatusLabel', 'NewTab', {'VerticalAlignment','top','WordWrap','on','Position',[10 10 200 175],'Text','VSA_rfsoc_new port: idle'}, '', ''
};
spec = cell2struct(R, {'ctor','CodeName','Parent','Props','CallbackProperty','Callback'}, 2);
end
