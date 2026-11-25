#!/usr/bin/env python3
"""The source of the Windows libmpv-2.dll, for the GPL (docs/PACKAGING.md §4).

windows/CMakeLists.txt ships shinchiro's mpv-winbuild-cmake build 20261111,
which compiles mpv, FFmpeg and the libraries they use from their git trees
and publishes only binaries. This finds the exact source it was built from,
and packs it for each release:

  windows_libmpv_sources.py lock --recipes <mpv-winbuild-cmake checkout>
      --log <the build's x86_64 job log> --earlier <the workflow's earlier
      x86_64 job logs...> --ffmpeg <hash> --out windows/packaging/libmpv-sources.lock.json
    Once, when the DLL changes. For each package in the DLL (mpv's DEPENDS,
    recursively), the commit or archive the build used:
      pinned  the recipe names a commit (GIT_RESET, or GIT_TAG with no remote)
              or an archive with its hash;
      named   in the DLL's file name (mpv) or the matching FFmpeg's (FFmpeg);
      log     the build's update step, or an earlier run's, printed the
              branch moving to it, and no later run printed it moving
              again. Every update step prints each branch that moved, so
              the earlier logs must cover every run since the first one
              (GitHub keeps 90 days);
      date    the branch didn't move in any of those runs: its last commit
              before the first of them;
      window  the build never updates it (curl), so its commit is lost: the
              release before it and every commit up to the next one, from
              the version the DLL reports.

  windows_libmpv_sources.py fetch --lock <lock> --out <file.tar.zst> [--label v2.0.0]
      [--cmake windows/CMakeLists.txt]
    In the release workflow. Downloads exactly what the lock names (git by
    commit, with submodules; archives checked by their hash), adds Rust
    crates (cargo vendor) and the recipes with their patches, and packs it.

Needs git, curl, tar with zstd, and cargo. Only reads the recipes: nothing
of theirs runs.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta

RECIPES_URL = 'https://github.com/shinchiro/mpv-winbuild-cmake.git'

# The build our libmpv-2.dll comes from (windows/CMakeLists.txt): release
# 20261111, workflow run 42927840447, recipes at this commit.
BUILD = {
    'release': '20261111',
    # The "mpv clang" workflow (mpv_clang.yml); its x86_64 job.
    'run': 'https://github.com/shinchiro/mpv-winbuild-cmake/actions/runs/42927840447',
    'recipes_commit': 'bda10a2816ce9908d419b3f4b564227330457e76',
    # From the release's file names: mpv-dev-x86_64-20261111-git-bcde6b93cc.7z
    # and ffmpeg-x86_64-git-<hash>.7z.
    'named': {'mpv': 'bcde6b93cc'},
    # curl is in mpv's DEPENDS but left out of the update step
    # (packages/CMakeLists.txt), so the build kept whatever its cache first
    # cloned, at a commit no log still shows. The DLL says "libcurl
    # 8.22.0-DEV": a commit after curl-8_21_0 and before curl-8_22_0, whose
    # history between them is linear.
    'window': {'curl': {'from': 'curl-8_21_0', 'to': 'curl-8_22_0',
                        'evidence': 'libmpv-2.dll reports libcurl 8.22.0-DEV'}},
}

# Set for x86_64 in cmake/packages_check.cmake and packages/x265.cmake.
X86_64_VARS = {
    '${ffmpeg_x265}': 'x265-8+10bit',
    '${ffmpeg_uavs3d}': 'uavs3d',
    '${ffmpeg_davs2}': 'davs2',
}


def run(*cmd, cwd=None, capture=False):
    r = subprocess.run(cmd, cwd=cwd, check=True, text=True,
                       stdout=subprocess.PIPE if capture else None)
    return r.stdout.strip() if capture else None


def recipes(root):
    """Every ExternalProject_Add block: name -> its text."""
    blocks = {}
    for f in sorted(glob.glob(os.path.join(root, 'packages', '*.cmake'))):
        text = open(f).read()
        for m in re.finditer(r'ExternalProject_Add\((\S+)(.*?)\n\)', text, re.S):
            blocks[m.group(1)] = m.group(2)
    return blocks


def key(block, name):
    m = re.search(rf'^\s+{name}\s+("[^"]*"|\S+)', block, re.M)
    return m.group(1).strip('"') if m else None


def depends(block):
    m = re.search(r'DEPENDS\s+(.*?)\n\s+[A-Z_]{3,}\s', block, re.S)
    return [X86_64_VARS.get(d, d) for d in m.group(1).split()] if m else []


def closure(blocks, root='mpv'):
    seen, todo = [], [root]
    while todo:
        n = todo.pop()
        if n in seen:
            continue
        if n not in blocks:
            sys.exit(f'no recipe for {n}')
        seen.append(n)
        todo += depends(blocks[n])
    return sorted(seen)


def parse_log(path):
    """From the update step: package -> (time it ran, {branch: new commit})."""
    steps, current = {}, None
    stamp = re.compile(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)\.\d+Z\s?(.*)')
    moved = re.compile(r'^\+?\s*[0-9a-f]+\.\.\.?([0-9a-f]+)\s+(\S+)\s+->\s+origin/(\S+)')
    for raw in open(path, errors='replace'):
        line = re.sub(r'\x1b\[[0-9;]*m', '', raw.rstrip('\n')).split('\t')[-1]
        m = stamp.search(line)
        if not m:
            continue
        when, text = m.group(1), m.group(2)
        step = re.search(r"Performing force-update step for '([^']+)'", text)
        if step:
            current = step.group(1)
            steps[current] = (when, {})
            continue
        if current and (mv := moved.match(text.strip())):
            steps[current][1][mv.group(2)] = mv.group(1)
        elif text.startswith('##[group]') and current:
            current = None  # the next step of the workflow
    return steps


def lock(args):
    blocks = recipes(args.recipes)
    head = run('git', '-C', args.recipes, 'rev-parse', 'HEAD', capture=True)
    if head != BUILD['recipes_commit']:
        sys.exit(f'recipes at {head}, the build used {BUILD["recipes_commit"]}')
    steps = parse_log(args.log)
    # name -> branch -> (run, commit): the latest move any run printed,
    # oldest log first so later ones win. The build's own log is last.
    earlier = sorted(args.earlier or [])
    last_move = {}
    for f in earlier + [args.log]:
        for n, (_, moves) in parse_log(f).items():
            for br, new in moves.items():
                last_move.setdefault(n, {})[br] = (os.path.basename(f), new)
    first = re.search(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)',
                      os.path.basename(earlier[0])) if earlier else None
    cache = args.cache or tempfile.mkdtemp(prefix='libmpv-src-')
    entries, seen_urls = [], {}
    for name in closure(blocks):
        b = blocks[name]
        url = key(b, 'GIT_REPOSITORY')
        archive = key(b, 'URL')
        if url is None and archive is None:
            # x265-10bit and the like: built from another package's source.
            entries.append({'name': name, 'kind': 'same-as', 'of': 'x265'})
            continue
        if archive:
            algo, _, digest = (key(b, 'URL_HASH') or '').partition('=')
            if not digest:
                sys.exit(f'{name}: an archive without a hash')
            entries.append({'name': name, 'kind': 'archive', 'url': archive,
                            'hash': f'{algo.lower()}:{digest.lower()}',
                            'how': 'pinned'})
            continue
        if url in seen_urls:
            entries.append({'name': name, 'kind': 'same-as', 'of': seen_urls[url]})
            continue
        seen_urls[url] = name
        tag, reset = key(b, 'GIT_TAG'), key(b, 'GIT_RESET')
        remote = key(b, 'GIT_REMOTE_NAME')
        submodules = key(b, 'GIT_SUBMODULES') != ''
        repo = os.path.join(cache, name + '.git')
        branch = tag if remote and tag else None
        if not os.path.isdir(repo):
            clone = ['git', 'clone', '--quiet', '--bare', '--filter=tree:0']
            if branch:
                clone += ['--single-branch', '--branch', branch]
            run(*clone, url, repo)
        else:
            run('git', '-C', repo, 'fetch', '--quiet', 'origin')
        if not branch:
            branch = run('git', '-C', repo, 'symbolic-ref', '--short', 'HEAD',
                         capture=True)
        window = BUILD['window'].get(name)
        if window:
            run('git', '-C', repo, 'fetch', '--quiet', 'origin',
                f'refs/tags/{window["from"]}:refs/tags/{window["from"]}',
                f'refs/tags/{window["to"]}:refs/tags/{window["to"]}')
            ends = {k: run('git', '-C', repo, 'rev-parse', f'{window[k]}^{{commit}}',
                           capture=True) for k in ('from', 'to')}
            merges = run('git', '-C', repo, 'rev-list', '--merges', '--count',
                         f'{ends["from"]}..{ends["to"]}', capture=True)
            if merges != '0':
                sys.exit(f'{name}: the window has merges, so patches cannot cover it')
            since = run('git', '-C', repo, 'log', '-1', '--format=%cI',
                        ends['from'], capture=True)
            entries.append({'name': name, 'kind': 'git-window', 'url': url,
                            'since': since,
                            'from': window['from'], 'from_commit': ends['from'],
                            'to': window['to'], 'to_commit': ends['to'],
                            'evidence': window['evidence'], 'how': 'window'})
            print(f'{name:22} window {window["from"]}..{window["to"]}', file=sys.stderr)
            continue
        pinned = reset or (tag if tag and not remote else None)
        named = BUILD['named'].get(name)
        if name == 'ffmpeg':
            named = args.ffmpeg
        when, moves = steps.get(name, (None, {}))
        evidence = None
        if pinned:
            how, ref = 'pinned', pinned
        elif named:
            how, ref = 'named', named
        elif branch in last_move.get(name, {}):
            how, (evidence, ref) = 'log', last_move[name][branch]
        else:
            if not when:
                sys.exit(f'{name}: not pinned, and not in the update step')
            # Before the first logged run (or this build, without earlier
            # logs): the branch hasn't moved since.
            cutoff = (first.group(1) + 'Z') if first else (
                datetime.fromisoformat(when) + timedelta(minutes=1)).isoformat() + 'Z'
            how, evidence = 'date', f'last commit before {cutoff}'
            ref = run('git', '-C', repo, 'rev-list', '-1', '--first-parent',
                      f'--before={cutoff}', branch, capture=True)
        commit = run('git', '-C', repo, 'rev-parse', '--verify', f'{ref}^{{commit}}',
                     capture=True)
        if how in ('log', 'date', 'named'):
            # It must be on the branch the build followed.
            subprocess.run(['git', '-C', repo, 'merge-base', '--is-ancestor',
                            commit, branch], check=True)
        entry = {'name': name, 'kind': 'git', 'url': url, 'branch': branch,
                 'commit': commit, 'how': how, 'submodules': submodules}
        # The files the build checked out (mostly: no test data).
        post = key(b, 'GIT_CLONE_POST_COMMAND') or ''
        if post.startswith('sparse-checkout set --no-cone '):
            entry['sparse'] = post.split()[3:]
        if evidence:
            entry['evidence'] = evidence
        entries.append(entry)
        print(f'{name:22} {how:6} {commit[:12]}', file=sys.stderr)
    out = {'build': BUILD, 'recipes': {'url': RECIPES_URL,
                                       'commit': BUILD['recipes_commit']},
           'packages': entries}
    with open(args.out, 'w') as f:
        json.dump(out, f, indent=1)
        f.write('\n')
    counts = {}
    for e in entries:
        counts[e.get('how', e['kind'])] = counts.get(e.get('how', e['kind']), 0) + 1
    print(f'{len(entries)} packages: {counts}', file=sys.stderr)


def fetch_git(url, commit, dest, submodules, depth='1', sparse=None, since=None):
    os.makedirs(dest)
    run('git', 'init', '--quiet', dest)
    run('git', '-C', dest, 'remote', 'add', 'origin', url)
    try:
        if depth is None:
            # The history back to `since` (for format-patch).
            run('git', '-C', dest, 'fetch', '--quiet', f'--shallow-since={since}',
                'origin', commit)
        else:
            run('git', '-C', dest, 'fetch', '--quiet', '--depth', depth, 'origin', commit)
    except subprocess.CalledProcessError:
        # Hosts that don't serve a commit by its hash: the whole history.
        run('git', '-C', dest, 'fetch', '--quiet', '--filter=blob:none', 'origin')
    if sparse:
        run('git', '-C', dest, 'sparse-checkout', 'set', '--no-cone', *sparse)
    run('git', '-C', dest, '-c', 'advice.detachedHead=false', 'checkout',
        '--quiet', commit)
    if submodules and os.path.exists(os.path.join(dest, '.gitmodules')):
        run('git', '-C', dest, 'submodule', 'update', '--quiet', '--init',
            '--recursive', '--depth', '1')


def check_cmake(path, build):
    """The lock must describe the DLL windows/CMakeLists.txt ships."""
    m = re.search(r'set\(CINEMAKOM_LIBMPV_VERSION "([^"]+)"\)', open(path).read())
    want = f'{build["release"]}-git-{build["named"]["mpv"]}'
    if not m or m.group(1) != want:
        sys.exit(f'{path} ships libmpv {m.group(1) if m else "?"}, the lock is for '
                 f'{want}: run the lock step for the new DLL (docs/PACKAGING.md §4)')


def fetch(args):
    data = json.load(open(args.lock))
    if args.cmake:
        check_cmake(args.cmake, data['build'])
    work = tempfile.mkdtemp(prefix='libmpv-src-')
    root = os.path.join(work, 'libmpv-sources')
    os.makedirs(os.path.join(root, 'packages'))
    rec = os.path.join(root, 'mpv-winbuild-cmake')
    fetch_git(data['recipes']['url'], data['recipes']['commit'], rec, False)
    shutil.rmtree(os.path.join(rec, '.git'))
    for e in data['packages']:
        dest = os.path.join(root, 'packages', e['name'])
        if e['kind'] == 'same-as':
            continue
        if e['kind'] == 'archive':
            os.makedirs(dest)
            file = os.path.join(dest, os.path.basename(e['url']))
            run('curl', '-fsSL', '--retry', '3', '-o', file, e['url'])
            algo, digest = e['hash'].split(':')
            if hashlib.new(algo, open(file, 'rb').read()).hexdigest() != digest:
                sys.exit(f'{e["name"]}: {e["url"]} does not match its hash')
            continue
        if e['kind'] == 'git-window':
            # The release before, and every commit after it up to the next
            # release as patches: the DLL's commit is one of them.
            clone = dest + '.git-work'
            # A day before, so the release itself is in the history.
            since = (datetime.fromisoformat(e['since']) - timedelta(days=1)).isoformat()
            fetch_git(e['url'], e['to_commit'], clone, False, depth=None, since=since)
            os.makedirs(dest)
            series = os.path.join(dest, f'{e["from"]}..{e["to"]}.patches')
            run('git', '-C', clone, 'format-patch', '--quiet', '-o', series,
                f'{e["from_commit"]}..{e["to_commit"]}')
            run('git', '-C', clone, 'checkout', '--quiet', e['from_commit'])
            run('git', '-C', clone, 'archive', '--prefix', f'{e["from"]}/',
                '-o', os.path.join(dest, f'{e["from"]}.tar'), 'HEAD')
            shutil.rmtree(clone)
            print(f'{e["name"]:22} {e["from"]}..{e["to"]}', file=sys.stderr)
            continue
        fetch_git(e['url'], e['commit'], dest, e['submodules'],
                  sparse=e.get('sparse'))
        if os.path.exists(os.path.join(dest, 'Cargo.lock')):
            # Rust crates (subrandr): what cargo downloaded for the build.
            run('cargo', 'vendor', '--locked', '--quiet', 'vendor', cwd=dest)
        for g in glob.glob(os.path.join(dest, '**', '.git'), recursive=True):
            shutil.rmtree(g) if os.path.isdir(g) else os.remove(g)
        print(f'{e["name"]:22} {e["commit"][:12]}', file=sys.stderr)
    shutil.copy(args.lock, os.path.join(root, 'libmpv-sources.lock.json'))
    with open(os.path.join(root, 'README.txt'), 'w') as f:
        f.write(README.format(label=args.label or '', **data['build']))
    run('tar', '-I', 'zstd -12 -T0', '-cf', os.path.abspath(args.out), '--sort=name',
        '--owner=0', '--group=0', '--mtime=@0', '-C', work, 'libmpv-sources')
    shutil.rmtree(work)


README = """\
Cinemakom {label} for Windows: the source of libmpv-2.dll.

libmpv-2.dll is shinchiro's mpv-winbuild-cmake build {release}
({run}). It is built from the recipes in mpv-winbuild-cmake/ (commit
{recipes_commit}, patches included) and from the packages in packages/.
libmpv-sources.lock.json lists each package's repository and commit, or
archive and hash, and how that was established:
  pinned  the recipe names it;
  named   in the release's file names (mpv, FFmpeg);
  log     a run's log (the build's, or an earlier one's) shows the update
          reaching it, and no later run shows it moving again;
  date    the branch didn't move in any logged run (from 2026-08-28):
          its last commit before then;
  window  curl: the build kept an old copy whose commit no record shows.
          The DLL reports libcurl 8.22.0-DEV, so it is one of the commits
          from curl-8_21_0 to curl-8_22_0: packages/curl has 8.21.0 and
          every commit after it, up to 8.22.0, as patches (git am).
Rust crates are in each package's vendor/ folder. Where a recipe checks
out only part of a repository (git sparse-checkout, mostly to leave out
test data), the package has only that part, as the build did.

mpv is GPL 2 or later; FFmpeg as built here is GPL too (it includes x264
and x265). Each package's license is in its folder. Cinemakom itself is MIT:
https://github.com/sharon-xa/cinemakom
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    lk = sub.add_parser('lock')
    lk.add_argument('--recipes', required=True)
    lk.add_argument('--log', required=True)
    lk.add_argument('--earlier', nargs='*', help="the workflow's earlier x86_64 logs, named <time>_<run>.log")
    lk.add_argument('--ffmpeg', required=True, help="FFmpeg's commit, from the release's file names")
    lk.add_argument('--out', required=True)
    lk.add_argument('--cache')
    fe = sub.add_parser('fetch')
    fe.add_argument('--lock', required=True)
    fe.add_argument('--out', required=True)
    fe.add_argument('--label')
    fe.add_argument('--cmake', help='windows/CMakeLists.txt: check it ships the DLL the lock is for')
    args = ap.parse_args()
    lock(args) if args.cmd == 'lock' else fetch(args)


if __name__ == '__main__':
    main()
