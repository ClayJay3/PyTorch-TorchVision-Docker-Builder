# This script builds pytorch wheel including libtorch for arm64 and python 3.9 with cuda support

docker buildx build . --build-arg '--oci-worker-gc --oci-worker-gc-keepstorage 50000' --platform=linux/arm64 --progress=plain --output type=local,dest=. -t build-torch-l4t:aarch64 ${pwd}
