# OpenFOAM&reg; wth OpenMP&reg; target offloading (using HMM) - AMD MI Instinct&trade; 

To take advantage of the [Heterogeneous Memory Management](https://www.kernel.org/doc/html/v5.0/vm/hmm.html) support on advanced devices, OpenFOAM is ported with OpenMP target offloading. The scripts in this repository can be used to configure and build OpenFOAM with HMM support.

---
## Requirements
The following dependencies must be resolved for a successful build on A+A platforms.
1. CMake (>3.22)
2. ROCm&trade; (> 6.0.0)
3. Clang-17 or latest with HMM and device support. (Comes packaged with ROCm)
4. MPI (tested with openmpi-v4.1.5) [[Build Instructions](#buid-openmpi)] 
5. UMPIRE (tested with v6.0.0) [[Build Instructions](#build-umpire)]

> NOTE 
> * The instructions here describe how to configure and install OpenFOAM on AMD platforms with MI Instinct&trade; cards (A+A).
> * To build OpenFOAM on NVIDIA platforms with CUDA, read the instuctions in [README-cuda](README-cuda.md) 

---
## Setup environment
1. Setup the ENV variables that are used by OpenFOAM
```bash
export MPI_PATH=<path-to>/ompi
export UMPIRE_PATH=<path-to>/umpire-6.0.0
export ROCM_PATH=<path-to>/rocm-version
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
       [--openfoam-version] OpenFOAM version (e.g.: 2206, etc.)
       [--cuda]             Build for NVIDIA platforms with CUDA
       [--load-benchmark]   Load OpenFOAM HPC Benchmarks
       [--load-benchmark-only]  Skip build and load the benchmakrs only
```
* `--prefix` can be used to specify a particular path/directory. By default, the current working dir (`pwd`) is considered.
* `--openfoam-version` is used to specify the OpenFOAM version to install. The OpenMP port is based on OpenFOAM-v2206 and has been updated for v2312.
* `--load-benchmark` configures and builds the benchmark (HPC_motorbike Large) case which will be used for performance measurements.

To install OpenFOAM, run the script as:
```bash
./build.sh --openfoam-version 2206 --load-benchmark
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

## Configuring HPC_motorbike case...
...

```
## Running the HPC_motorbike benchmark
Before running the benchmark ensure that `MPI_PATH`, `ROCM_PATH` and `UMPIRE_PATH` are correctly setup in your [environment](#setup-environment), else OpenFOAM enviroment and executables will not be loaded. Source the enviroment with: 
```bash 
cd <your-path-to>/OpenFOAM-v2206
source scripts/setup.sh
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
./bench-hpc-motorbike.sh -g N
```
where `N` is the number of GPUs (the script is designed to extract `MAX_DEVICES`) availble on the system. Once the mesh is generated, for the subsequent runs, use:
```bash
./bench-hpc-motorbike.sh -r -g N
```
For example, for first run, with 1 GPU:
```bash
./bench-hpc-motorbike.sh -g 1
```
and then for a subsequent run, with 4 GPUs:
```bash
./bench-hpc-motorbike.sh -r -g 4
```

### Successful run
A successful run should look like:
```bash
Time = 20

diagonalPBiCGStab:  Solving for Ux, Initial residual = 0.0012770619467, Final residual = 9.68393190595e-05, No Iterations 13
diagonalPBiCGStab:  Solving for Uy, Initial residual = 0.058762886126, Final residual = 0.00414545948022, No Iterations 11
diagonalPBiCGStab:  Solving for Uz, Initial residual = 0.0245825566577, Final residual = 0.00185066934045, No Iterations 12
snGrad: line 52
in PCG
diagonalPCG:  Solving for p, Initial residual = 0.0134491004365, Final residual = 0.000133887686834, No Iterations 234
time step continuity errors : sum local = 0.000408001378213, global = 1.83175309432e-05, cumulative = 0.000657052277727
test_type: T==Foam::Vector<double>
diagonalPBiCGStab:  Solving for omega, Initial residual = 0.000194058179271, Final residual = 1.8420802286e-05, No Iterations 2
bounding omega, min: -2891.51191655 max: 1302799.38762 average: 4493.30914702
diagonalPBiCGStab:  Solving for k, Initial residual = 0.00208209895293, Final residual = 0.000163406832348, No Iterations 2
I AM IN kOmegaSSTBase<BasicEddyViscosityModel>::correctNut
ExecutionTime = 548 s  ClockTime = 1571 s

End

Using:
  case     : <path-to>/OpenFOAM_HMM/HPC_Benchmark/incompressible/simpleFoam/HPC_motorbike/Large/v1912
  log      : log.simpleFoam-1-ranks-1-apu
  database : <path-to>/OpenFOAM_HMM/OpenFOAM-v2206/bin/tools/foamLog.db
  awk file : logs/foamLog.awk
  files to : logs

Executing: awk -f logs/foamLog.awk log.simpleFoam-1-ranks-1-apu

Generated XY files for:
    ...
    executionTime
    ...
End
--------------------
    FOMs:
--------------------
    1. Execution Time     (s): 548
    2. Time per Time-Step (s): 6.44
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
> Platform        : HIP
> Git commit      : git-hash -- git-branch
> =============================================================
> ```
 
## Configuring Dependencies

### Buid OpenMPI
To build OpenMPI, use the `./build_ompi.sh` script. Ensure that correct versions of `UCX`, `OMPI`, and their intended paths (in `--prefix`) are provided, and then run with:
```bash
./build_ompi.sh
```
> NOTE:
> If you want to install MPI library in `/usr`, `/opt` and any other system level directory, then you'll need to run the script with `sudo`, as:
```bash
sudo ./build_ompi.sh
```
### Build UMPIRE
To build, [Umpire 6.0.0](https://github.com/LLNL/umpire), use the following steps:
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
@last updated	: Dec, 2024<br>
