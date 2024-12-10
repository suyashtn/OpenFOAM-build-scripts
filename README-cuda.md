# OpenFOAM&reg; wth OpenMP&reg; target offloading (using HMM) - NVIDIA platforms
To take advantage of the [Heterogeneous Memory Management](https://www.kernel.org/doc/html/v5.0/vm/hmm.html) support on advanced devices, OpenFOAM is ported with OpenMP target offloading. The scripts in this repository can be used to configure and build OpenFOAM with HMM support.

---
## Requirements
The following dependencies must be resolved for a successful build on NVIDIA platforms.
1. HMM support enabled on NVIDIA platform [[Instructions]](#enabling-and-detecting-hmm)
2. CMake - 3.22 or newer
3. CUDA (tested with CUDA-12.2, preferred nvidia/hpc_sdk 23.9)
4. Clang-17 or latest with HMM and device support. [[Build Instructions](#building-clang-from-source-with-device-nptx-support)]
5. MPI (tested with v5.0.0rc12) [[Build Instructions](#buid-openmpi)] 
6. UMPIRE (tested with v6.0.0) [[Build Instructions](#build-umpire)]

---
## Setup environment
1. Ensure that the llvm/clang compilers ([build instructions](#building-clang-from-source-with-device-nptx-support)) are in your paths
```bash
export PATH=<path-to-llvm>/bin:$PATH
export LD_LIBRARY_PATH=<path-to-llvm>/lib:$LD_LIBRARY_PATH
```
2. Setup the ENV variables that are used by OpenFOAM
```bash
export MPI_PATH=<path-to>/ompi
export UMPIRE_PATH=<path-to>/umpire-6.0.0
export CUDA_PATH=<path-to>/cuda-12.2
```

## Build OpenFOAM
Once the [environment](#setup-environment) is correctly setup, a convenient  `build.sh` script is included here, which can be executed with following options:
```bash
$ ./build.sh -h

This is a build script designed to configure and install OpenFOAM with OpenMP offloading using HMM.
=================================
usage: ./build.sh

       -h | --help          Prints the usage
       [--prefix]           Base installation directory, defaults to CWD
       [--openfoam-version] OpenFOAM version (e.g.: 2112, 2206, etc.)
       [--cuda]             Build for NVIDIA platforms with CUDA
       [--load-benchmark]   Load OpenFOAM HPC Benchmarks
       [--load-benchmark-only]  Skip build and load the benchmakrs only
```
* `--prefix` can be used to specify a particular path/directory. By default, the current working dir (`pwd`) is considered.
* `--openfoam-version` is used to specify the OpenFOAM version to install. The OpenMP port is based on OpenFOAM-v2206, and thus the recommended version is `2206` (else build may yield mangled file paths).
* `--cuda` must be specified to build on NVIDIA platforms with CUDA
* `--load-benchmark` configures and builds the benchmark (HPC_motorbike Large) case which will be used for performance measurements.

To install OpenFOAM, run the script as:
```bash
./build.sh --cuda --openfoam-version 2206 --load-benchmark
```

### Successful installation
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
Host:                GPU8518
OS:                  Linux version 5.15.0-86-generic
-------------------------------------------------------------------------------

Main OpenFOAM env variables :
-------------------------------------------------------------------------------
Environment           FileOrDirectory                          Valid      Crit
-------------------------------------------------------------------------------
$WM_PROJECT_USER_DIR  /home/suyashtn/OpenFOAM/suyashtn-v2206    no        no
$WM_THIRD_PARTY_DIR   /home/suyashtn/OpenFOAM/ThirdParty-v2206  yes       maybe
$WM_PROJECT_SITE      [env variable unset]                                no
-------------------------------------------------------------------------------

OpenFOAM env variables in PATH :
-------------------------------------------------------------------------------
Environment           FileOrDirectory                          Valid Path Crit
-------------------------------------------------------------------------------
$WM_PROJECT_DIR       /home/suyashtn/OpenFOAM/OpenFOAM-v2206    yes  yes  yes

$FOAM_APPBIN          .../platforms/linux64ClangDPInt32Opt/bin  yes  yes  yes
$FOAM_SITE_APPBIN     .../platforms/linux64ClangDPInt32Opt/bin  no        no
$FOAM_USER_APPBIN     .../platforms/linux64ClangDPInt32Opt/bin  no        no
$WM_DIR               ...uyashtn/OpenFOAM/OpenFOAM-v2206/wmake  yes  yes  often
-------------------------------------------------------------------------------

OpenFOAM env variables in LD_LIBRARY_PATH :
-------------------------------------------------------------------------------
Environment           FileOrDirectory                          Valid Path Crit
-------------------------------------------------------------------------------
$FOAM_LIBBIN          .../platforms/linux64ClangDPInt32Opt/lib  yes  yes  yes
$FOAM_SITE_LIBBIN     .../platforms/linux64ClangDPInt32Opt/lib  no        no
$FOAM_USER_LIBBIN     .../platforms/linux64ClangDPInt32Opt/lib  no        no
$FOAM_EXT_LIBBIN      ...206/platforms/linux64ClangDPInt32/lib  yes  yes  maybe
$MPI_ARCH_PATH        /usr                                      yes   no  yes
-------------------------------------------------------------------------------

Software Components
-------------------------------------------------------------------------------
Software     Version    Location  
-------------------------------------------------------------------------------
flex         2.6.4      /usr/bin/flex                                          
make         4.3        /usr/bin/make                                          
wmake        2206       /home/suyashtn/OpenFOAM/OpenFOAM-v2206/wmake/wmake     
clang        18.0.0     /home/suyashtn/clang-17/llvm-project/install/bin/clang 
clang++      18.0.0     /home/suyashtn/clang-17/llvm-project/install/bin/clang++
-------------------------------------------------------------------------------
icoFoam      exists     ...M-v2206/platforms/linux64ClangDPInt32Opt/bin/icoFoam

Summary
-------------------------------------------------------------------------------
Base configuration ok.
Critical systems ok.

Done

## Configuring HPC_motorbike case...
...

```
## Running the HPC_motorbike benchmark
Before running the benchmark ensure that `MPI_PATH`, `CUDA_PATH` and `UMPIRE_PATH` are correctly setup in your [environment](#setup-environment), else OpenFOAM enviroment and executables will not be loaded. Source the enviroment with: 
```bash 
cd <your-path-to>/OpenFOAM-v2206
source scripts/MEMO_SETUP.sh
```

To run the bechmark, a convenient script is included:
```bash
$ ./bench-hpc-motorbike.sh -h

=================================
usage: ./bench-hpc-motorbike.sh

       -h | --help      Prints the usage
       -c | --clean     Clean the case directory
       -d | --device    Specify target to offload to CUDA or HIP (default: HIP)
       -g | --ngpus     #GPUs to be used (between 1-4), defaults to 1
       -j | --threads   #OpenMP threads (default: 1)
       -n | --mpi-ranks #MPI ranks to be used. (default ranks=gpus)
       -l | --log-suffix user-defined name/suffix to add to logs (default: apu)
       -t | --time-steps #time-steps to run for (default: 20) 
       -r | --run-only  skip mesh build, and directly run the case
```
* `-g` can be used to sepcify the number of devices that must be used. Currently the script is designed to run with max. 4 devices. 
* `-d` can be used to specify target offloading to device HIP or CUDA (Default: HIP)
* `-n` specified the number of MPI ranks that must be used. (Default: ranks=gpus)
* `-t` to change the number of time-steps/iterations to run for. (Default:, 20 time-steps)
* `-j` prescribes the number of OpenMP threads that can be used. (Default: 1 thread)
* `-r` can be used to skip mesh generation phase and run the solvers directly. NOTE: This can save time (>30mins) provided the mesh is already generated. Thus, it is recommended that when re-running the benchmark with a different `-g`, `-n`, `-j`, or `-t` after the first successful run, use this option to save computational time.
* `-l` is optional and can be used to specify the name/suffix for naming the `log*` files dumped during the simulations, and to help in housekeeping.


For **first time** execution, when *no mesh* exists, use the command:
```bash
./bench-hpc-motorbike.sh -d CUDA -g N -l H100-HMM
```
where `N` is the number of GPUs (the script is designed to extract `MAX_DEVICES`) availble on the system. Once the mesh is generated, for the subsequent runs, use:
```bash
./bench-hpc-motorbike.sh -r -d CUDA -g N -l H100-HMM
```
For example, for first run, with 1 GPU:
```bash
./bench-hpc-motorbike.sh -d CUDA -g 1 -l H100-HMM
```
and then for a subsequent run, with 4 GPUs:
```bash
./bench-hpc-motorbike.sh -r -d CUDA -g 4 -l H100-HMM
```
### Successful run
A successful run should look like:
```bash
Time = 20

diagonalPBiCGStab:  Solving for Ux, Initial residual = 0.00128030523777, Final residual = 7.48225220065e-05, No Iterations 13
diagonalPBiCGStab:  Solving for Uy, Initial residual = 0.0584804584279, Final residual = 0.00279416571509, No Iterations 13
diagonalPBiCGStab:  Solving for Uz, Initial residual = 0.0245002472714, Final residual = 0.00207957275825, No Iterations 13
snGrad: line 52
in PCG
diagonalPCG:  Solving for p, Initial residual = 0.0134621018993, Final residual = 0.000134396992145, No Iterations 232
time step continuity errors : sum local = 0.000411132206547, global = 2.33469010682e-05, cumulative = 0.000672479466326
test_type: T==Foam::Vector<double>
diagonalPBiCGStab:  Solving for omega, Initial residual = 0.000194095156931, Final residual = 1.84246708292e-05, No Iterations 2
bounding omega, min: -2658.06294602 max: 1302799.64426 average: 4495.21878157
diagonalPBiCGStab:  Solving for k, Initial residual = 0.00208017961934, Final residual = 0.000163431682384, No Iterations 2
I AM IN kOmegaSSTBase<BasicEddyViscosityModel>::correctNut
ExecutionTime = 1763.13 s  ClockTime = 2970 s

End

Using:
  case     : <path-to>/OpenFOAM_HMM/HPC_Benchmark/incompressible/simpleFoam/HPC_motorbike/Large/v1912
  log      : log.simpleFoam-1-ranks-1-H100-HMM
  database : <path-to>/OpenFOAM_HMM/OpenFOAM-v2206/bin/tools/foamLog.db
  awk file : logs/foamLog.awk
  files to : logs

Executing: awk -f logs/foamLog.awk log.simpleFoam-1-ranks-1-H100-HMM

Generated XY files for:
    ...
    executionTime
    ...
End
--------------------
    FOMs:
--------------------
    1. Execution Time     (s): 1763.13
    2. Time per Time-Step (s): 73.26
-------------------
```
> NOTE: 
> * A `helper.sh` is included and is called during the run that helps set the affinity. A basic implementation is provided that uses `Socket 0` and associated GPUs + CPUs for the runs. 
> * The FOMs shown are for depiction and actual data may change with more porting and optimisations. 
> * To keep track of progress, at the top of the run, the git commit and config is displayed:
> ```bash
> ============================================================
> Running HPC_motorbike (Large) benchmark
> 
> MPI Ranks       : 1
> OMP_NUM_THREADS : 1
> APUs/GPUs       : 1
> Platform        : CUDA
> Git commit      : git-hash -- git-branch
> =============================================================
> ```
 
## Configuring Dependencies
### Enabling and detecting HMM
To enable HMM support on NVIDIA platforms, you'll need: 
* NVIDIA CUDA 12.2 with the open-source r535_00 driver or newer. See  [NVIDIA Open GPU Kernel Modules Installation Documentation](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#nvidia-open-gpu-kernel-modules) for details.
* A sufficiently recent Linux kernel: 6.1.24+, 6.2.11+, or 6.3+.
* A GPU with one of the following supported architectures: NVIDIA Turing, NVIDIA Ampere, NVIDIA Ada Lovelace, NVIDIA Hopper, or newer.
* A 64-bit x86 CPU.
For more details follow the guidance in the [blog](https://developer.nvidia.com/blog/simplifying-gpu-application-development-with-heterogeneous-memory-management/).

### Building Clang from source with device (NPTX) support
On H100, we need latest clang, to support `sm_90`. Follow these steps:
1. `git clone https://github.com/llvm/llvm-project.git && cd llvm-project`
2. `cd llvm-project && mkdir build install && cd build`
3. Use CMake to configure and build
```bash
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$(pwd)/../install -DLLVM_TARGETS_TO_BUILD="NVPTX;X86" -DLIBOMPTARGET_DEVICE_ARCHITECTURES="sm_90" -DLLVM_ENABLE_PROJECTS="clang;openmp" -DLLVM_ENABLE_RUNTIMES=all -DLLVM_INCLUDE_TESTS=off ../llvm

make -j 
make install
```
> NOTE:
> If you want to install clang in `/usr`, `/opt` and any other system level directory, then you'll need to run the script with `sudo`, as:
```bash
sudo make install
```
Once installed, make sure the compiler in added to your [environment](#setup-environment).

### Buid OpenMPI
To build OpenMPI, use the `./build_ompi.sh` script. Ensure that correct versions of `UCX`, `OMPI`, and their intended paths (in `--prefix`) are provided, and then run with:
```bash
./build_ompi.sh --cuda
```
> NOTE:
> If you want to install MPI library in `/usr`, `/opt` and any other system level directory, then you'll need to run the script with `sudo`, as:
```bash
sudo ./build_ompi.sh --cuda
```
### Build UMPIRE
To build, [Umpire 6.0.0](https://github.com/LLNL/umpire), with device and managed memory support with CUDA, use the following steps:
1. `git clone --progress --recursive https://github.com/LLNL/umpire -b v6.0.0`
2. navigate to build dir: `mkdir -p build && cd build`:
3. Configure and build with CMake (and `sudo` if necessary):
```bash
cmake \
  -DCMAKE_INSTALL_PREFIX="<path-to-install>" \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_FORTRAN=ON \
  -DENABLE_CUDA=ON \
  -DENABLE_EXAMPLES=OFF \
  -DENABLE_TESTS=OFF \
  -DENABLE_GMOCK=OFF \
  -DENABLE_BENCHMARKS=OFF \
  -DUMPIRE_ENABLE_FILESYSTEM=OFF \
../umpire

make -j $(nproc)
sudo make install -j $(nproc)
```

To build, [Umpire 6.0.0](https://github.com/LLNL/umpire), without device support use the following steps:
1. `git clone --progress --recursive https://github.com/LLNL/umpire -b v6.0.0`
2. navigate to build dir: `mkdir -p build && cd build`:
3. Configure and build with CMake (and `sudo` if necessary):
```bash
cmake \
  -DCMAKE_INSTALL_PREFIX="<path-to-install>" \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_FORTRAN=ON \
  -DENABLE_EXAMPLES=OFF \
  -DENABLE_TESTS=OFF \
  -DENABLE_GMOCK=OFF \
  -DENABLE_BENCHMARKS=OFF \
  -DUMPIRE_ENABLE_FILESYSTEM=OFF \
../umpire

make -j $(nproc)
sudo make install -j $(nproc)
```


<!-- ---
## References
1. OpenFOAM website: https://www.openfoam.com
2. OpenFOAM repository: https://develop.openfoam.com/Development/openfoam.git
3. PETSc website: https://www.mcs.anl.gov/petsc/index.html
4. PETSc internal repository: https://github.com/AMD-HPC/PETSc
5. PETSc official repository: https://gitlab.com/petsc/petsc.git
6. PETSc4FOAM: https://develop.openfoam.com/modules/external-solver
---

@author	      : Suyash Tandon<br>
@last updated	: Oct 20, 2022<br>
