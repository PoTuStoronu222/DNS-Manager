#!/usr/bin/env python3
"""Check that the self-contained installer stages the exact runtime scripts."""
import os
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
source = (root / 'dns-manager-luci.sh').read_text(encoding='utf-8')
start = source.index('install_dnscrypt_assets() (\n')
end = source.index('\n)\n\ninstall_files()', start) + 2
function = source[start:end]
pattern = r'cat > "\$_dc_stage/([^"\n]+)" <<\'(EOF_DNSCRYPT_ASSET_[0-9]+)\'\n(.*?)\n\2\n'
assets = re.findall(pattern, function, re.DOTALL)
assert len(assets) == 8
for name, _, content in assets:
    assert content + '\n' == (root / 'libexec' / name).read_text(encoding='utf-8'), name

with tempfile.TemporaryDirectory(prefix='dnscrypt-assets-') as tmp:
    destination = pathlib.Path(tmp) / 'installed'
    env = {**os.environ, 'DNS_MANAGER_DNSCRYPT_INSTALL_DIR': str(destination)}
    result = subprocess.run(['sh'], input=function + '\ninstall_dnscrypt_assets\n',
                            text=True, capture_output=True, env=env)
    assert result.returncode == 0, result.stderr
    for name, _, content in assets:
        path = destination / name
        assert path.read_text(encoding='utf-8') == content + '\n'
        assert os.access(path, os.X_OK)

    # A syntax error in one staged asset must be detected before any file is
    # replaced. The existing installation remains available to the caller.
    before = {name: (destination / name).read_bytes() for name, _, _ in assets}
    name, marker, _ = assets[-1]
    broken = re.sub(r'(cat > "\$_dc_stage/' + re.escape(name) + r'" <<\'' + marker +
                    r'\'\n).*?(\n' + marker + r'\n)', r'\1if\2', function,
                    count=1, flags=re.DOTALL)
    assert broken != function
    result = subprocess.run(['sh'], input=broken + '\ninstall_dnscrypt_assets\n',
                            text=True, capture_output=True, env=env)
    assert result.returncode != 0
    assert all((destination / name).read_bytes() == old for name, old in before.items())
    assert not list(destination.glob('.stage.*'))

print('DNSCrypt installer assets match source and stage before replacement')
