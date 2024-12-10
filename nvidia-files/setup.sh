

export OMP_NUM_THREADS=1
export OMPX_DISABLE_USM_MAPS=1

#set CUDA, MPI and UMPIRE paths
export CUDA4FOAM=${CUDA_PATH:-/urs/local/cuda}
export MPI4FOAM=${MPI_PATH:-/opt/ompi}
export UMPIRE4FOAM=${UMPIRE_PATH:-/opt/umpire-6.0.0}

#set OMPI compilers
export OMPI_CXX=clang++
export OMPI_CC=clang

#add OMPI and ROCm to PATH and LD_LIBRARY_PATH
export PATH=${MPI4FOAM}/bin:$PATH
export LD_LIBRARY_PATH=${MPI4FOAM}/lib:$LD_LIBRARY_PATH
export LIBRARY_PATH=${MPI4FOAM}/lib:$LIBRARY_PATH

export PATH=${CUDA4FOAM}/bin:$PATH
export LD_LIBRARY_PATH=${CUDA4FOAM}/lib64:$LD_LIBRARY_PATH
export LIBRARY_PATH=${CUDA4FOAM}/lib64:$LIBRARY_PATH

#source OpenFOAM environment
source ./etc/bashrc

#
# End of file
# Author: Suyash Tandon




