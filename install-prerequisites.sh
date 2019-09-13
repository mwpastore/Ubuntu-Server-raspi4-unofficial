#!/bin/bash
set -euo pipefail
IFS=$'\t\n'

apt-get -qq install \
  bison \
  build-essential \
  coreutils \
  curl \
  flex \
  gpg \
  gpgv \
  libgmp-dev \
  libmpc-dev \
  libmpfr-dev \
  libssl-dev \
  qemu-system-arm \
  zsync

exit
