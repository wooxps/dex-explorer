"""Publish a tested, commit-pinned modular release using Git Credential Manager.

Credentials stay in memory and are never written into the repository or logs.
Run with --publish to update wooxps/dex-explorer.
"""
import argparse
import json
import os
import subprocess
import urllib.request
from package_runtime import ROOT, package, loader


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--message',default='Update Dex')
    args = parser.parse_args()
    package()
    if not args.publish:
        print('Release packaged. Pass --publish to validate and publish it.')
        return
    env = {**os.environ, 'GIT_TERMINAL_PROMPT':'0', 'GCM_INTERACTIVE':'Never'}
    def git(*arguments, capture=False):
        result = subprocess.run(['git', *arguments], cwd=ROOT, env=env, check=True,
                                text=True, capture_output=capture)
        return result.stdout.strip() if capture else None
    import sys
    tools = ROOT/'.tools/bin'
    subprocess.run([sys.executable,str(ROOT/'tests/run_checks.py'),'--luau',str(tools/'luau.exe'),
                    '--compiler',str(tools/'luau-compile.exe')],check=True)
    subprocess.run([sys.executable,str(ROOT/'tests/runtime_checks.py')],check=True)

    if (ROOT/'mcp/package.json').exists():
        mcp_tests=sorted((ROOT/'mcp/tests').glob('*.test.mjs'))
        assert mcp_tests, 'Missing Dex MCP tests'
        subprocess.run(['node','--test',*[str(path) for path in mcp_tests]],cwd=ROOT/'mcp',check=True)
        subprocess.run(['node','scripts/build.mjs'],cwd=ROOT/'mcp',check=True)
    credentials = subprocess.run(['git','credential','fill'],input='protocol=https\nhost=github.com\n\n',
                                 env=env,text=True,capture_output=True,check=True)
    fields = dict(line.split('=',1) for line in credentials.stdout.splitlines() if '=' in line)
    token = fields.get('password')
    if not token:
        raise SystemExit('Git Credential Manager has no GitHub credential.')
    def api(path, data=None):
        request = urllib.request.Request('https://api.github.com'+path,
            data=json.dumps(data).encode() if data is not None else None,
            headers={'Authorization':'Bearer '+token,'User-Agent':'DexExplorer-Publisher',
                     'Accept':'application/vnd.github+json','Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=30) as response:
            return json.load(response)
    repo = api('/repos/wooxps/dex-explorer')
    assert repo['permissions']['push'], 'Repository is not writable'
    assert git('remote','get-url','origin',capture=True)==repo['clone_url'], 'Unexpected Git remote'
    assert git('branch','--show-current',capture=True)=='main', 'Publish from main'
    # Explicit publish list excludes local tools, executor settings, reference
    # dumps, legacy vendor bundles, backups and generated offline builds.
    paths=['src','mcp','docs/mcp','docs/LUAU-LICENSE.txt','docs/PLUGINS.md','docs/USSI-LICENSE.txt',
           'main.lua','header.lua','studio_assets.lua','manifest.json','README.md',
           'scripts/embed_native_find_icons.py','scripts/embed_current_find_assets.py','scripts/extract_resize_cursors.py','scripts/embed_quick_action_icons.py','scripts/generate_editor_signatures.py',
           'LICENSE','BUILDING.md',
           'build.py','build.bat','tools.lock.json','selene.toml','dex_executor.yml',
           '.gitignore','.gitattributes','scripts/package_runtime.py','scripts/compact_hosted_source.py',
           'scripts/publish_github.py','scripts/build_studio_test.py','scripts/package_react.py','scripts/vendor_react.py','scripts/embed_studio_images.py','scripts/embed_editor_menu_assets.py','scripts/embed_transform_icons.py',
           'scripts/embed_gui_editor_assets.py','scripts/validate_client.luau','scripts/validate_icons.luau','scripts/validate_reconstructor.luau','scripts/status_reconstructor.luau','scripts/profile_bytecode_format.luau','scripts/profile_runtime_evidence.luau','scripts/profile_inference.luau','scripts/benchmark_client.luau','scripts/stage_client.py','tests']
    git('add','--',*paths)
    changed = subprocess.run(['git','diff','--cached','--quiet'],cwd=ROOT).returncode
    if changed:
        git('commit','-m',args.message)
    source_ref = git('rev-parse','HEAD',capture=True)
    entry = loader(source_ref)
    (ROOT/'loader.lua').write_text(entry,encoding='utf-8')
    subprocess.run([str(tools/'luau-compile.exe'),str(ROOT/'loader.lua')],stdout=subprocess.DEVNULL,check=True)
    git('add','loader.lua')
    if subprocess.run(['git','diff','--cached','--quiet'],cwd=ROOT).returncode:
        git('commit','-m','Update loader')
    git('push','-u','origin','main')
    print('Published '+repo['html_url'])
    print('Source pin: '+source_ref)


if __name__ == '__main__':
    main()
