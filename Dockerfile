# ##################################################################################
# Setup Nvidia CUDA for Jetson
# ##################################################################################
#FROM nvcr.io/nvidia/l4t-ml:r32.6.1-py3
FROM ubuntu:18.04 as cuda-devel
# Configuration Arguments
ARG V_CUDA_MAJOR=10
ARG V_CUDA_MINOR=2
ARG V_L4T_MAJOR=32
ARG V_L4T_MINOR=6
ENV V_CUDA=${V_CUDA_MAJOR}.${V_CUDA_MINOR}
ENV V_CUDA_DASH=${V_CUDA_MAJOR}-${V_CUDA_MINOR}
ENV V_L4T=r${V_L4T_MAJOR}.${V_L4T_MINOR}
# Expose environment variables everywhere
ENV CUDA=${V_CUDA_MAJOR}.${V_CUDA_MINOR}
# Accept default answers for everything
ENV DEBIAN_FRONTEND=noninteractive
# Fix CUDA info
ARG DPKG_STATUS
# Add NVIDIA repo/public key and install VPI libraries
RUN echo "$DPKG_STATUS" >> /var/lib/dpkg/status \
    && echo "[Builder] Installing Prerequisites" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates software-properties-common curl gnupg2 apt-utils \
    && echo "[Builder] Installing CUDA Repository" \
    && curl https://repo.download.nvidia.com/jetson/jetson-ota-public.asc > /etc/apt/trusted.gpg.d/jetson-ota-public.asc \
    && echo "deb https://repo.download.nvidia.com/jetson/common ${V_L4T} main" >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list \
    && echo "deb https://repo.download.nvidia.com/jetson/t186 ${V_L4T} main" >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list \
    && echo "[Builder] Installing CUDA System" \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    cuda-libraries-${V_CUDA_DASH} \
    cuda-libraries-dev-${V_CUDA_DASH} \
    cuda-nvtx-${V_CUDA_DASH} \
    cuda-minimal-build-${V_CUDA_DASH} \
    cuda-license-${V_CUDA_DASH} \
    cuda-command-line-tools-${V_CUDA_DASH} \
    libnvvpi1 vpi1-dev \
    && ln -s /usr/local/cuda-${V_CUDA} /usr/local/cuda \
    && rm -rf /var/lib/apt/lists/*
# Update environment
ENV LIBRARY_PATH=/usr/local/cuda/lib64/stubs
RUN ln -fs /usr/share/zoneinfo/America/Chicago /etc/localtime
# ##################################################################################
# Create PyTorch Docker Layer
# We do this seperately since else we need to keep rebuilding
# ##################################################################################
FROM --platform=$BUILDPLATFORM ubuntu:18.04 as downloader-pytorch
# Configuration Arguments
# https://github.com/pytorch/pytorch
ARG V_PYTORCH=v1.7.1
# https://github.com/pytorch/vision
ARG V_PYTORCHVISION=v0.8.2
# https://github.com/pytorch/audio
ARG V_PYTORCHAUDIO=v0.7.2
# Install Git Tools
RUN apt-get update \
    && apt-get install -y --no-install-recommends software-properties-common apt-utils git \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean
# Accept default answers for everything
ENV DEBIAN_FRONTEND=noninteractive
# Clone Source
RUN git clone --recursive --branch ${V_PYTORCH} http://github.com/pytorch/pytorch
# ##################################################################################
# Build PyTorch for Jetson (with CUDA)
# ##################################################################################
FROM cuda-devel as builder
# Configuration Arguments
ARG V_PYTHON_MAJOR=3
ARG V_PYTHON_MINOR=8
ENV V_PYTHON=${V_PYTHON_MAJOR}.${V_PYTHON_MINOR}
# Accept default answers for everything
ENV DEBIAN_FRONTEND=noninteractive
# Download Common Software
RUN apt-get update \
    && apt-get install -y clang build-essential bash ca-certificates git wget cmake curl software-properties-common ffmpeg libsm6 libxext6 libffi-dev libssl-dev xz-utils zlib1g-dev liblzma-dev
# Setting up Python 3.9
WORKDIR /install
RUN add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y python${V_PYTHON} python${V_PYTHON}-dev python${V_PYTHON}-venv python${V_PYTHON_MAJOR}-tk \
    && rm /usr/bin/python \
    && rm /usr/bin/python${V_PYTHON_MAJOR} \
    && ln -s $(which python${V_PYTHON}) /usr/bin/python \
    && ln -s $(which python${V_PYTHON}) /usr/bin/python${V_PYTHON_MAJOR} \
    && curl --silent --show-error https://bootstrap.pypa.io/get-pip.py | python
# PyTorch - Build - Source Code Setup 
# copy everything from the downloader-pytorch layer /torch to /torch on this one
COPY --from=downloader-pytorch /pytorch /pytorch
WORKDIR /pytorch
# PyTorch - Build - Prerequisites
# Set clang as compiler
# clang supports the ARM NEON registers
# GNU GCC will give "no expression error"
ARG CC=clang
ARG CXX=clang++
# Set path to ccache
ARG PATH=/usr/lib/ccache:$PATH
# Other arguments
ARG USE_CUDA=ON
ARG USE_CUDNN=ON
ARG BUILD_CAFFE2_OPS=0
ARG USE_FBGEMM=0
ARG USE_FAKELOWP=0
ARG BUILD_TEST=0
ARG USE_MKLDNN=0
ARG USE_NNPACK=0
ARG USE_XNNPACK=0
ARG USE_QNNPACK=0
ARG USE_PYTORCH_QNNPACK=0
ARG TORCH_CUDA_ARCH_LIST="5.3;6.2;7.2"
ARG USE_NCCL=0
ARG USE_SYSTEM_NCCL=0
ARG USE_OPENCV=0
ARG USE_DISTRIBUTED=0
ARG PYTORCH_BUILD_VERSION=${V_PYTORCH}
ARG PYTORCH_BUILD_NUMBER=1 
# Build
RUN cd /pytorch \
    && rm build/CMakeCache.txt || : \
    && sed -i -e "/^if(DEFINED GLIBCXX_USE_CXX11_ABI)/i set(GLIBCXX_USE_CXX11_ABI 1)" CMakeLists.txt \
    && pip install setuptools==59.5.0 \
    && pip install -r requirements.txt \
    #&& python setup.py bdist_wheel \
    && cd ..
# ##################################################################################
# Prepare Artifact
# ##################################################################################
#FROM scratch as artifact
#COPY --from=builder /pytorch/dist/* /

# ##################################################################################
# Compile torchvision extension.
# ##################################################################################
# Download pre-compiled pytorch 1.7.0 from my github.
RUN git clone https://github.com/ClayJay3/PyTorch-Torchvision-Docker-Compile.git \ 
    && cd PyTorch-Torchvision-Docker-Compile \
    && pip install torch-1.7.0a0-cp38-cp38-linux_aarch64.whl \
    && cd ..

# Build torchvision
RUN git clone --branch v0.8.2 https://github.com/pytorch/vision.git \
	&& cd vision \
	&& python3 setup.py bdist_wheel \
	&& cd ..
	

