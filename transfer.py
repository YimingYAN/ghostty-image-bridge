#!/usr/bin/env python3
"""Upload to an explicitly recognized foreground SSH or mosh destination, then paste."""
import ipaddress, json, os, re, shlex, subprocess, sys, uuid
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
    program = os.path.basename(parts[0]) if parts else ''
    if program == 'mosh-client':
        # The installed mosh wrapper execs mosh-client with an informational
        # argument: "-# <original arguments> |", followed by IP and UDP port.
        # ps prints argv without quoting; accept only the plain invocation.
        match = re.fullmatch(r'-# ([^\s|]+) \| (\S+) ([0-9]+)', ' '.join(parts[1:]))
        if not match:
            raise RuntimeError('Use plain mosh user@host; this mosh session could not be identified')
        destination, address, port = match.groups()
        try:
            ipaddress.ip_address(address)
        except ValueError:
            raise RuntimeError('Invalid mosh server address') from None
        if not 1 <= int(port) <= 65535:
            raise RuntimeError('Invalid mosh server port')
    elif program in ('ssh', 'mosh') and len(parts) == 2:
        destination = parts[1]
    else:
        raise RuntimeError('The focused terminal is not a supported direct SSH or mosh session')
    # Never infer a destination from an IP, title, or arbitrary remote output.
    if destination.startswith('-') or destination not in HOSTS:
        raise RuntimeError('Use plain ssh or mosh with a destination listed in ~/.config/ghostty-image-bridge/hosts.json')
    return destination

def upload(host, path):
    if host not in HOSTS:
        raise RuntimeError('Unconfigured SSH destination')
    opts = ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10']
    directory = run(['/usr/bin/ssh', *opts, host,
        'umask 077; mkdir -p "$HOME/.cache/clipboard-images" && cd "$HOME/.cache/clipboard-images" && pwd'])
    if not re.fullmatch(r'/[A-Za-z0-9_./-]+', directory):
        raise RuntimeError('Unexpected remote upload directory')
    name = re.sub(r'[^A-Za-z0-9._-]', '_', Path(path).name)[:180] or 'file'
    remote = directory + '/' + str(uuid.uuid4()) + '-' + name
    run(['/usr/bin/scp', '-q', *opts, path, host + ':' + remote])
    return remote

def main():
    files_mode = sys.argv[1:2] == ['--files']
    if files_mode:
        ident, pid, *paths = sys.argv[2:]
    else:
        path, ident, pid = sys.argv[1:]
        paths = [path]
    try:
        if not paths or any(not Path(path).is_file() for path in paths):
            raise RuntimeError('Copy regular files in Finder; folders and special files are unsupported')
        if context() != (ident, pid):
            raise RuntimeError('Terminal focus changed; files were not sent')
        command = run(['/bin/ps', '-p', pid, '-o', 'command='])
        host = target(command)
        remotes = [upload(host, path) for path in paths]
        if context() != (ident, pid) or run(['/bin/ps', '-p', pid, '-o', 'command=']) != command:
            raise RuntimeError('Session changed; files uploaded to ' + ', '.join(remotes) + ' but were not pasted')
        # Upload paths contain only shell-safe characters. Never press Enter.
        apple('tell application "Ghostty"\ninput text ' + json.dumps(' '.join(remotes) + ' ') +
              ' to (first terminal whose id is ' + json.dumps(ident) + ')\nend tell')
    finally:
        # Finder originals belong to the user; only generated images are temporary.
        if not files_mode:
            os.unlink(path)
if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
