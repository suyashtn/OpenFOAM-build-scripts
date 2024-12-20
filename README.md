# OpenFOAM with PETSc
---
```
#------------------------------------------------------------------------------
# =========               |
# \\      /  F ield       | OpenFOAM: The Open Source CFD Toolbox  
#  \\    /   O peration   |
#   \\  /    A nd         |www.openfoam.com
#    \\/     M anipulation|
#------------------------------------------------------------------------------
```
Configure [OpenFOAM](https://www.openfoam.com) with [PETSc](https://www.mcs.anl.gov/petsc/index.html) to accelerate solvers on the GPUs.

## Requirements
OpenFOAM and PETSc have the following dependencies. The installation has been tested
with the mentioned versions of the libraries,

1. gcc-8.3.1
2. MPI (openmpi, etc.): openmpi/5.0.3
3. boost/1.75.0
4. cmake/3.23.0
5. ROCm/6.3.0 or CUDA/12.6
6. BLAS (openblas, etc.): blas/3.8.0-8  

## Build OpenFOAM and PETSc
1. Clone the build scripts - 
```bash
$ git clone --progress -b petsc https://github.com/suyashtn/OpenFOAM-build-scripts OpenFOAM
```
2. Navigate to `OpenFOAM/` dir from above, and use the `build.sh` script - a one-stop bash script designed to configure and install PETSc, the interface [PETSc4FOAM](https://develop.openfoam.com/modules/external-solver) and OpenFOAM. All the libraries are stitched together so that PETSc solvers can be employed to offload work on GPUs when running OpenFOAM benchmarks and cases. 
```bash
$ ./build.sh -h

This is a build script designed to configure and install OpenFOAM with OpenMP offloading using HMM.
=================================
usage: ./build.sh

       -h | --help          Prints the usage
       [--prefix]           Base installation directory, defaults to CWD
       [--openfoam-version] OpenFOAM version (e.g.: 2206, etc.)
       [--cuda]             Build for NVIDIA platforms with CUDA
```
* `--prefix` can be used to specify a particular path/directory. By default, the current working dir (`pwd`) is considered.
* `--openfoam-version` is used to specify the desired OpenFOAM version from [openfoam.com](https://www.openfoam.com/current-release) to install.

To install OpenFOAM, run the script as:
```bash
./build.sh --openfoam-version 2406
```

### Successful OpenFOAM installation
A successful installation with `build.sh` script will print the following: 
``` bash
========================================
Done OpenFOAM Allwmake
========================================

Check OpenFOAM installation
use: foamInstallationTest
=================================
Executing foamInstallationTest

Basic setup :
-------------------------------------------------------------------------------
OpenFOAM:            OpenFOAM-v2206
ThirdParty:          ThirdParty-v2206
Shell:               bash
Host:                <hostname>
OS:                  Linux version 5.18.2-<platform>-ubuntu-22.04+
-------------------------------------------------------------------------------

Main OpenFOAM env variables :
-------------------------------------------------------------------------------
Environment           FileOrDirectory                          Valid      Crit
-------------------------------------------------------------------------------
$WM_PROJECT_USER_DIR  /home/user/OpenFOAM/user-v2206            no        no
$WM_THIRD_PARTY_DIR   /home/user/OpenFOAM/ThirdParty-v2206      yes       maybe
$WM_PROJECT_SITE      [env variable unset]                                no
-------------------------------------------------------------------------------

OpenFOAM env variables in PATH :
-------------------------------------------------------------------------------
Environment           FileOrDirectory                          Valid Path Crit
-------------------------------------------------------------------------------
$WM_PROJECT_DIR       /home/user/OpenFOAM/OpenFOAM-v2206        yes  yes  yes

$FOAM_APPBIN          .../platforms/linux64ClangDPInt32Opt/bin  yes  yes  yes
$FOAM_SITE_APPBIN     .../platforms/linux64ClangDPInt32Opt/bin  no        no
$FOAM_USER_APPBIN     .../platforms/linux64ClangDPInt32Opt/bin  no        no
$WM_DIR               /home/user/OpenFOAM/OpenFOAM-v2206/wmake  yes  yes  often
-------------------------------------------------------------------------------

OpenFOAM env variables in LD_LIBRARY_PATH :
-------------------------------------------------------------------------------
Environment           FileOrDirectory                          Valid Path Crit
-------------------------------------------------------------------------------
$FOAM_LIBBIN          .../platforms/linux64ClangDPInt32Opt/lib  yes  yes  yes
$FOAM_SITE_LIBBIN     .../platforms/linux64ClangDPInt32Opt/lib  no        no
$FOAM_USER_LIBBIN     .../platforms/linux64ClangDPInt32Opt/lib  no        no
$FOAM_EXT_LIBBIN      ...206/platforms/linux64ClangDPInt32/lib  yes  yes  maybe
$MPI_ARCH_PATH        /opt/ompi-llvm-4.1.5                      yes  yes  yes
-------------------------------------------------------------------------------

Software Components
-------------------------------------------------------------------------------
Software     Version    Location  
-------------------------------------------------------------------------------
flex         2.6.4      /usr/bin/flex                                          
make         4.3        /usr/bin/make                                          
wmake        2206       ...don/rocshore/OpenFOAM_HMM/OpenFOAM-v2206/wmake/wmake
clang        17.0.0     /opt/rocm-6.0.0/llvm/bin/clang                   
clang++      17.0.0     /opt/rocm-6.0.0/llvm/bin/clang++                 
-------------------------------------------------------------------------------
icoFoam      exists     ...M-v2206/platforms/linux64ClangDPInt32Opt/bin/icoFoam

Summary
-------------------------------------------------------------------------------
Base configuration ok.
Critical systems ok.

Done
```
>NOTE:
> * The script downloads `scotch`. The version can be altered by changing the variable `s_v` in L#81.
> * Similarly, PETSc is downloaded in the ThirdParty-<version> directory. Version is prescribed by the variable `p_v` in line# 95.
> * Since PETSc needs to be configured with either [HIP](https://docs.amd.com/) or CUDA, a specially configured script `makePETSC.hip` or `makePETSC.cuda` is used. 

### Before running OpenFOAM
Due to nature of OpenFOAM and PETSc installation, it is important to ensure that the environment variables are properly initialized.
1. OpenFOAM: `source <your-path>/OpenFOAM-<version>/etc/bashrc`
2. PETSc:
```
eval $(foamEtcFile -sh -config petsc -- -force)
foamHasLibrary -verbose petscFoam
```
  >*NOTE*: The above commands can be added to `.bashrc` or similar shell script, so that environment can be loaded automatically for every new terminal.

---
## Configuring the HPC Benchmarks
The standard HPC benchmark problems for OpenFOAM include the following tests:
1. Lid-driven cavity: An 2D/3D incompressible flow problem. Three workloads available.
2. Motorbike: A 3D unsteady flow problem which incorporates some basic turbulence modeling. Three workloads available.
 
`load_benchmark.sh` configures the HPC benchmark cases:
```bash
$ ./load_benchmark.sh
```

#### Disclaimers
- The sparse-GEMM feature in Kokkos uses sparse APIs in CUDA and ROCm stacks. The `S` workload of `Lid_driven_cavity` benchmark requires ~30GB of GPU memory, and therefore larger problems cannot fit on a single GPU. 
- Large portions of the GAMG preconditioner in PETSc are resident on the CPU, and is known to have poor scaling on multiple GPUs.

---
## License
1. OpenFOAM: The source code is licensed under GNU Public License version 3.0 or later. Check license of OpenFOAM [here](https://develop.openfoam.com/Development/openfoam#license).
2. PETSc: The source code is distributed under 2-Clause BSD License and the license file can be found [here](https://gitlab.com/petsc/petsc/-/blob/main/LICENSE).
3. PETSc4FOAM: The source code, in line with OpenFOAM and PETSc, is licensed under GNU Public License version 3.0 or later. Check [here](https://develop.openfoam.com/modules/external-solver#license).

---
## References
1. OpenFOAM website: https://www.openfoam.com
2. OpenFOAM repository: https://develop.openfoam.com/Development/openfoam.git
3. PETSc website: https://www.mcs.anl.gov/petsc/index.html
4. PETSc official repository: https://gitlab.com/petsc/petsc.git
5. PETSc4FOAM: https://develop.openfoam.com/modules/external-solver
---

@author	      : Suyash Tandon<br>
@last updated	: Dec, 2024
