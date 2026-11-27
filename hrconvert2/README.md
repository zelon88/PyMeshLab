# HRConvert2's build of PyMeshLab

HRConvert2 converts 3D models with PyMeshLab. This branch builds PyMeshLab 2025.7.post1 with HRConvert2's patches to
the model readers it uses, & publishes the wheels HRConvert2 installs. Nothing else differs from upstream.

It follows HRConvert2's procedure for a fault in a dependency: fork, patch, build, point, pull. Each fault is reported
upstream. Once an upstream release carries the fixes, HRConvert2 points back at it & this build is retired.

## What is patched

| Folder | Applies to | At |
|---|---|---|
| `patches/vcglib` | vcglib, the readers for PLY, STL, OFF, Collada & CTM, & the clean up MeshLab runs after a load | c94ef4e1, the commit PyMeshLab pins |
| `patches/meshlab` | MeshLab's 3DS & X3D plugins | d876376, the commit PyMeshLab pins |
| `patches/lib3ds` | lib3ds 1.3.0, which MeshLab downloads & builds for 3DS | Debian's `lib3ds_1.3.0.orig.tar.gz` |
| `patches/openctm` | OpenCTM 1.0.3, which MeshLab downloads & builds for CTM | Debian's `openctm_1.0.3+dfsg1.orig.tar.bz2` |

`vcglib/0001` & `vcglib/0002` are vcglib's own commits ea8126f4 & 7a9ba565, taken from its devel branch.

`patched.sha256` holds every file the patches touch as it was tested.

## Building

As PyMeshLab builds on Linux, with one more step before the build:

    git submodule update --init --recursive
    bash hrconvert2/apply.sh
    sh scripts/Linux/0_setup_env.sh
    sh scripts/Linux/1_build.sh
    sh scripts/Linux/2_deploy.sh
    python -m pip wheel . -w wheels/ --no-deps

`apply.sh` checks the pins, applies the patches, fetches lib3ds & OpenCTM from Debian's archive, checks each by
SHA-256, unpacks them where MeshLab's build looks for them, patches them, & checks every patched file against
`patched.sha256`. `src/CMakeLists.txt` refuses to configure a tree it has not patched, & has MeshLab build those two
libraries from the patched copies only. Set `HRCONVERT2_ARCHIVES` to a folder holding both archives to build without
the network.

The wheel keeps upstream's version, 2025.7.post1. `pymeshlab/HRCONVERT2_BUILD.txt` inside it names the build & its
patches.

## Releases

`.github/workflows/HRConvert2Wheels.yml` is run by hand. It builds for Python 3.14 on x86_64 & arm64 Linux, tests
the build & the wheel, & with "release" ticked publishes the wheels & `SHA256SUMS` as a release tagged
`hrconvert2-<PYML_VERSION>-<BUILD_NUMBER>`. Every action it uses is pinned to a commit.

Its tests:

- `test/samples.tsv`: every MeshLab sample in a format HRConvert2 reads loads with the vertex & face counts stock
  PyMeshLab 2025.7.post1 gives.
- `test/models.tsv`: a small model in each of those formats does the same.
- PyMeshLab's own tests.
- Where the repository holds the `HRC_REPRODUCERS_KEY` secret, the files in `test/reproducers.tar.gz.enc` each end
  as their list says.

`test/readers.py` runs a list. Each model loads in a process of its own, under a time limit & a data limit.

## Pointing back

When upstream releases the fixes, HRConvert2's manifest points at the upstream release again, & this branch stops
being built.
