#!/usr/bin/env python3
"""Upload to an explicitly recognized foreground SSH destination, then paste."""
import json, os, re, shlex, subprocess, sys, uuid
from pathlib import Path
CONFIG = Path.home() / '.config/ghostty-image-bridge/hosts.json'
try:
    HOSTS = set(json.loads(CONFIG.read_text())['hosts'])
except (FileNotFoundError, KeyError, TypeError, ValueError):
    HOSTS = set()

def run(args, **kwargs):
    return subprocess.check_output(args, text=True, timeout=45, **kwargs).strip()
def apple(script):
    return run(['/usr/bin/osascript', '-e', script])
def context():
    result = apple('tell application "Ghostty"\nset t to focused terminal of selected tab of front window\nreturn (id of t) & "|" & (pid of t as text)\nend tell')
    ident, pid = result.split('|')
    if not re.fullmatch(r'[A-Za-z0-9-]+', ident) or not pid.isdigit():
        raise RuntimeError('Invalid terminal identity')
    return ident, pid

def target(command):
    parts = shlex.split(command)
    if not parts or os.path.basename(parts[0]) != 'ssh':
        raise RuntimeError('The focused terminal is not a direct SSH session')
    # Only plain interactive SSH connections are supported. Never infer a host
    # from arbitrary command arguments, titles, or remote output.
    if len(parts) != 2 or parts[1] not in HOSTS:
        raise RuntimeError('Use plain ssh user@host with a destination listed in ~/.config/ghostty-image-bridge/hosts.json')
    return parts[1]

def upload(host, path):
    if host not in HOSTS:
        raise RuntimeError('Unconfigured SSH destination')
    opts = ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10']
    directory = run(['/usr/bin/ssh', *opts, host,
        'umask 077; mkdir -p "$HOME/.cache/clipboard-images" && cd "$HOME/.cache/clipboard-images" && pwd'])
    if not re.fullmatch(r'/[A-Za-z0-9_./-]+', directory):
        raise RuntimeError('Unexpected remote upload directory')
    remote = directory + '/clipboard-' + str(uuid.uuid4()) + '.png'
    run(['/usr/bin/scp', '-q', *opts, path, host + ':' + remote])
    return remote

def main():
    path, ident, pid = sys.argv[1:]
    try:
        if context() != (ident, pid):
            raise RuntimeError('Terminal focus changed; image was not sent')
        command = run(['/bin/ps', '-p', pid, '-o', 'command='])
        host = target(command)
        remote = upload(host, path)
        if context() != (ident, pid) or run(['/bin/ps', '-p', pid, '-o', 'command=']) != command:
            raise RuntimeError('Session changed; image uploaded to ' + remote + ' but was not pasted')
        # No newline or Enter: the user remains in control of submitting input.
        apple('tell application "Ghostty"\ninput text ' + json.dumps(remote + ' ') +
              ' to (first terminal whose id is ' + json.dumps(ident) + ')\nend tell')
    finally:
        os.unlink(path)
if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
