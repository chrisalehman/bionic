#!/usr/bin/env python3
# tests/lib/callgraph.py — who calls whom across the parts of a split shell script.
#
#   python3 -I tests/lib/callgraph.py <dispatcher> <part>...
#
# The dispatcher is the file that loads the parts; every other argument is a part. A function belongs to the
# file that defines it (a line `name() {`, at any indentation). A call is the function's name as a word in
# another file's text, comments stripped (a line whose first mark is `#`, and a ` #` to the end of a line).
# Calls into and out of the dispatcher are the common case and are not listed; a call from one part to a
# function another part defines is.
#
# Output, one line each, in this order:
#   call <from> <to> <function>   every cross-part call, sorted
#   load <from> <to>              every pair of parts with calls one way only: <from> needs <to> loaded
#   then one verdict line: `callgraph: ok — ...` and exit 0, or `callgraph: FAIL — ...` and exit 1, after
#   one line per fault:
#   two-way <a> <b>               two parts call each other: <a> calls <b> and <b> calls <a>
#   order <from> <to>             <from> needs <to>, and the dispatcher does not load <to> before <from>
#   unloaded <part>               the dispatcher has no `. "<...>/<part dir>/<part file>"` line for the part (a load
#                                 is matched on the part's directory name and file name, so a library of the same
#                                 file name elsewhere is not taken for it)
#   twice <function> <file> <file>  one name defined in two files: the later load silently replaces the first
# Exit 2: a file cannot be read, or no part was named.
import re
import sys

DEF = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*(\{|\(|$)')
WORD = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
LOAD = re.compile(r'(?:^|[\s;&|({!])\.\s+"?[^"\s]*?([^/"\s]+/[^/"\s]+\.sh)"?')


def text_of(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as fh:
            return fh.read().split('\n')
    except OSError as e:
        print(f'callgraph: cannot read {path}: {e.strerror}', file=sys.stderr)
        sys.exit(2)


def strip(line):
    if line.lstrip().startswith('#'):
        return ''
    return re.sub(r'(^|\s)#.*$', '', line)


def main(argv):
    if len(argv) < 3:
        print('usage: python3 -I tests/lib/callgraph.py <dispatcher> <part>...', file=sys.stderr)
        return 2
    disp, parts = argv[1], argv[2:]
    files = [disp] + parts
    lines = {f: [strip(l) for l in text_of(f)] for f in files}
    owner, faults = {}, []
    for f in files:
        for l in lines[f]:
            m = DEF.match(l)
            if not m:
                continue
            name = m.group(1)
            if name in owner and owner[name] != f:
                faults.append(f'twice {name} {owner[name]} {f}')
            owner.setdefault(name, f)
    calls = set()
    for f in parts:
        for l in lines[f]:
            m = DEF.match(l)
            body = l[m.end(1):] if m else l
            for w in WORD.findall(body):
                to = owner.get(w)
                if to is not None and to != f and to != disp:
                    calls.add((f, to, w))
    for c in sorted(calls):
        print('call', *c)
    pairs = {(a, b) for a, b, _ in calls}
    order = []
    for l in lines[disp]:
        for m in LOAD.finditer(l):
            order.append(m.group(1))
    base = {p: '/'.join(p.rsplit('/', 2)[-2:]) for p in parts}
    pos = {}
    for p in parts:
        if base[p] in order:
            pos[p] = order.index(base[p])
        else:
            faults.append(f'unloaded {p}')
    loads = 0
    for a, b in sorted(pairs):
        if (b, a) in pairs:
            if a < b:
                faults.append(f'two-way {a} {b}')
            continue
        print('load', a, b)
        loads += 1
        if a in pos and b in pos and pos[b] > pos[a]:
            faults.append(f'order {a} {b}')
    for x in faults:
        print(x)
    if faults:
        print(f'callgraph: FAIL — {len(faults)} fault(s) among {len(parts)} part(s)')
        return 1
    print(f'callgraph: ok — {len(parts)} part(s), {loads} declared load(s), no two-way pair')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
