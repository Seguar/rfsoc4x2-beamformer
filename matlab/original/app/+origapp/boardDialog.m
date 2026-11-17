function choice = boardDialog(note,address)
%BOARDDIALOG Ask for the board address when the automatic search found none.
% Returns struct('action',"connect"|"demo"|"cancel",'host',address).
choice = struct('action',"cancel",'host',"");
fig = uifigure('Name','RFSoC Beamformer','Position',[0 0 540 270],'Resize','off');
movegui(fig,'center');
grid = uigridlayout(fig,[4 3]);
grid.RowHeight = {'1x',22,30,36}; grid.ColumnWidth = {'1x','1x','1x'}; grid.Padding = [18 16 18 16];
message = uilabel(grid,'Text',char(note),'WordWrap','on','VerticalAlignment','top');
message.Layout.Row = 1; message.Layout.Column = [1 3];
label = uilabel(grid,'Text','Board IP address','FontWeight','bold');
label.Layout.Row = 2; label.Layout.Column = [1 3];
field = uieditfield(grid,'text','Value',char(address),'Placeholder','for example 192.168.2.99');
field.Layout.Row = 3; field.Layout.Column = [1 3];
connect = uibutton(grid,'Text','Connect','ButtonPushedFcn',@(~,~)onConnect());
connect.Layout.Row = 4; connect.Layout.Column = 1;
demo = uibutton(grid,'Text','Run simulation','ButtonPushedFcn',@(~,~)done("demo",""));
demo.Layout.Row = 4; demo.Layout.Column = 2;
cancel = uibutton(grid,'Text','Close','ButtonPushedFcn',@(~,~)done("cancel",""));
cancel.Layout.Row = 4; cancel.Layout.Column = 3;
fig.CloseRequestFcn = @(~,~)done("cancel","");
uiwait(fig);
if isvalid(fig), delete(fig); end

    function onConnect()
        try
            origapp.BoardLink.parseAddress(field.Value);
        catch err
            message.Text = err.message; return
        end
        done("connect",strtrim(string(field.Value)));
    end

    function done(action,host)
        choice = struct('action',action,'host',host);
        uiresume(fig);
    end
end
