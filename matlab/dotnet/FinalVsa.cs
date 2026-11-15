using System;
using Agilent.SA.Vsa;
namespace FinalValidation { public static class FinalVsa {
 public static void Restore(Measurement m) { m.SetMeasurementExtension(typeof(Agilent.SA.Vsa.CustomOfdm.MeasurementExtension)); }
 public static string Apply(Measurement m, float[] preamble, float[] pilots) {
 Restore(m);
 var e=Agilent.SA.Vsa.CustomOfdm.MeasurementExtension.CastToExtensionType(m.MeasurementExtension);
 e.FftLength=256; e.GuardLowerSubcarriers=104; e.GuardUpperSubcarriers=103; e.GuardInterval=.25; e.OfdmSystemSampleFrequency=125e6;
 e.SearchLength=8192.0/125e6; e.ResultLengthSelection=Agilent.SA.Vsa.CustomOfdm.ResultLengthSelection.Manual; e.ResultLength=12;
 int[] map=new int[49*12], mod=new int[49*12];
 for(int s=0;s<12;s++) for(int b=0;b<49;b++) { int i=s*49+b; bool active=b!=24; map[i]=!active?4:s<4?3:(b==3||b==17||b==31||b==45)?1:0; mod[i]=active&&s>=4?2:0; }
 e.SetResourceMap(map); e.SetResourceModulations(mod); e.SetPreambleValues(preamble); e.SetPilotValues(pilots); e.ResultLength=12;
 if(e.FftLength!=256||e.GuardInterval!=.25||e.OfdmSystemSampleFrequency!=125e6||e.ResultLength!=12) throw new Exception("Settings readback failed FFT="+e.FftLength+" CP="+e.GuardInterval+" Fs="+e.OfdmSystemSampleFrequency+" Result="+e.ResultLength);
 return "Mode="+m.MeasurementExtensionType+" Fs="+e.OfdmSystemSampleFrequency+" FFT="+e.FftLength+" CP="+e.GuardInterval+" Result="+e.ResultLength+" Search="+e.SearchLength+" Active=48 Pilots=-21,-7,7,21";
 }
 public static string Licenses(Application app) {
 string s="MinimumVersion="+app.Licenses.MinimumVersion+"\n"; foreach(var p in typeof(Application).GetProperties()) if(p.Name.ToLower().Contains("demo")||p.Name.ToLower().Contains("trial")||p.Name.ToLower().Contains("version")) { try{s+=p.Name+"="+p.GetValue(app,null)+"\n";}catch{} }
 for(int k=0;k<app.Licenses.Count;k++) {var l=app.Licenses[k]; s+=l.Description+" Valid="+l.IsValid+" Enabled="+l.Enabled+" Restricted="+l.IsRestricted+" Version="+l.Version+" Expiration="+l.Expiration+"\n";} return s;
 }
}}
