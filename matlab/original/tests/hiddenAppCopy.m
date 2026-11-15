function [appPath,cleanup] = hiddenAppCopy(originalPath)
% Test-only copy: generated App Designer code briefly shows a window before
% startupFcn can apply visible=false. Change exactly that one line in a copy.
root=tempname; mkdir(root); appPath=fullfile(root,'app'); copyfile(originalPath,appPath);
file=fullfile(appPath,'VSA_rfsoc_refactor_exported.m');
text=fileread(file); text=strrep(text,sprintf('\r\n'),newline); lines=splitlines(text);
needle='            app.RFSoCBeamformerUIFigure.Visible = ''on'';';
index=find(strcmp(lines,needle));
assert(isscalar(index),'fixture:GeneratedVisibility','Expected one generated show line.');
lines{index}='            app.RFSoCBeamformerUIFigure.Visible = ''off''; % TEST VARIANT ONLY';
fid=fopen(file,'w','n','UTF-8'); assert(fid>=0); guard=onCleanup(@()fclose(fid));
fprintf(fid,'%s',strjoin(lines,newline)); clear guard;
cleanup=onCleanup(@()removeCopy(root,appPath));
end
function removeCopy(root,appPath)
if contains([path pathsep],[appPath pathsep]), rmpath(appPath); end
if isfolder(root), rmdir(root,'s'); end
end
