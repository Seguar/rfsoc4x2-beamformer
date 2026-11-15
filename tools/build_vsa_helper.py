"""Build our typed VSA configuration helper against a locally installed SDK."""
import argparse
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--interfaces-dir', required=True)
    parser.add_argument('--out', default='out/FinalVsa.dll')
    parser.add_argument('--compiler', help='Optional path to the .NET Framework C# compiler')
    args = parser.parse_args()
    sdk = Path(args.interfaces_dir).resolve()
    references = [sdk/'Agilent.SA.Vsa.Interfaces.dll',
                  sdk/'Agilent.SA.Vsa.CustomOfdm.Interfaces.dll']
    compiler = Path(args.compiler) if args.compiler else (
        Path(os.environ.get('WINDIR', 'C:/Windows')) /
        'Microsoft.NET/Framework64/v4.0.30319/csc.exe')
    for path in [compiler, *references]:
        if not path.is_file():
            parser.error('Required local compiler/SDK file missing: '+str(path))
    output = Path(args.out).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).resolve().parents[1]/'matlab/dotnet/FinalVsa.cs'
    subprocess.run([str(compiler), '/nologo', '/target:library',
        '/out:'+str(output), *('/reference:'+str(p) for p in references),
        str(source)], check=True)
    print(output)


if __name__ == '__main__':
    main()
