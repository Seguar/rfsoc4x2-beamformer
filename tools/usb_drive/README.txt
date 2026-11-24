RFSoC 4x2 Beamformer - USB drive of the board
=============================================

1. MATLAB Runtime R2026a (once per PC, about 4 GB installed):
   open MATLAB_Runtime_R2026a_Update_5_win64 and run setup.exe
   (or skip this step if MATLAB R2026a is installed; then put its bin\win64
   folder first on PATH, as start.cmd does).

2. Copy the folder RFSoCBeamformer to the PC (for example the Desktop) and
   double-click RFSoCBeamformer.exe. It finds this board over USB
   (192.168.3.1) and starts a session at 5.2 GHz. The first start unpacks
   the application and takes a few minutes.

Details: https://github.com/Seguar/rfsoc4x2-beamformer (docs/STANDALONE.md)
The runtime installer is MathWorks' MATLAB_Runtime_R2026a_Update_5_win64.zip,
unpacked unchanged.
