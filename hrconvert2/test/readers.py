#!/usr/bin/env python3
# HRConvert2's build of PyMeshLab. Loads each model a list names, each in a process of its own, as HRConvert2 loads
# one, with MeshSet.load_new_mesh(), & compares what happened with what the list expects. A load runs under a time
# limit & a 2 GiB data limit, so a model that faults, hangs or asks for memory without end fails its line, & never
# the run.
#
#   python hrconvert2/test/readers.py <list.tsv> [--root <folder the list's paths are under>] [--module <folder>]
#
# --module names the folder holding a built pymeshlab package, which is imported in place of an installed one. Each
# load runs in Python's isolated mode, so without --module it can only import the installed package, never a pymeshlab
# folder in the current one.
# Each line of the list is a path, a tab & what is expected: "loaded <vertices> <faces>" or "refused". A refusal is
# PyMeshLab raising PyMeshLabException. Anything else, a signal, the time limit or another exit, matches neither, & a
# path that names no file is "missing", so a list run from the wrong folder fails instead of passing as refusals.
# It prints a line a model & exits 1 if any line differs from the list.

import os
import resource
import subprocess
import sys

TIME_LIMIT = 60
DATA_LIMIT = 2 * 1024 * 1024 * 1024

LOADER = r'''
import sys
if sys.argv[2]:
    sys.path.insert(0, sys.argv[2])
import pymeshlab
meshSet = pymeshlab.MeshSet()
try:
    meshSet.load_new_mesh(sys.argv[1])
except pymeshlab.PyMeshLabException:
    print("refused")
    sys.exit(0)
mesh = meshSet.current_mesh()
print("loaded %d %d" % (mesh.vertex_number(), mesh.face_number()))
'''


def limitChild():
    resource.setrlimit(resource.RLIMIT_DATA, (DATA_LIMIT, DATA_LIMIT))


def loadOne(path, module):
    if not os.path.isfile(path):
        return 'missing'
    environment = dict(os.environ, QT_QPA_PLATFORM='offscreen')
    try:
        result = subprocess.run([sys.executable, '-I', '-c', LOADER, path, module], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=TIME_LIMIT, preexec_fn=limitChild, env=environment)
    except subprocess.TimeoutExpired:
        return 'time limit'
    lines = [line for line in result.stdout.decode('utf-8', 'replace').splitlines() if line.startswith(('loaded', 'refused'))]
    if result.returncode < 0:
        return 'signal %d' % -result.returncode
    if result.returncode != 0 or not lines:
        return 'exit %d' % result.returncode
    return lines[-1]


def main():
    arguments = sys.argv[1:]
    if not arguments or arguments[0].startswith('--'):
        sys.exit(__doc__ if __doc__ else 'Usage: readers.py <list.tsv> [--root <folder>] [--module <folder>]')
    listPath = arguments[0]
    root = os.path.dirname(os.path.abspath(listPath))
    module = ''
    if '--root' in arguments:
        root = os.path.abspath(arguments[arguments.index('--root') + 1])
    if '--module' in arguments:
        module = os.path.abspath(arguments[arguments.index('--module') + 1])
    differences = 0
    count = 0
    with open(listPath, encoding='utf-8') as handle:
        for line in handle:
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            path, expected = line.split('\t')
            outcome = loadOne(os.path.join(root, path), module)
            count += 1
            same = (outcome == expected)
            if not same:
                differences += 1
            print('%-4s %-60s %-24s %s' % ('OK' if same else 'DIFF', path, outcome, '' if same else 'expected ' + expected))
            sys.stdout.flush()
    print('%d models, %d as expected, %d not.' % (count, count - differences, differences))
    sys.exit(1 if differences else 0)


if __name__ == '__main__':
    main()
