#!/usr/bin/env bash

set -ex

# mapd-core v 4.5.0 (or older) hardcodes /usr/bin/java Grab
# Calcite.cpp with a fix
# (https://github.com/omnisci/mapd-core/pull/316) from a repo:
wget https://raw.githubusercontent.com/omnisci/mapd-core/7c1faa09dd88d0cc735b629048f74d71baa9179f/Calcite/Calcite.cpp
mv Calcite.cpp Calcite/

# conda build cannot find boost libraries from
# ThirdParty/lib. Actully, moving environment boost libraries to
# ThirdParty/lib does not make much sense. The following is just a
# quick workaround of the problem:
sed -i 's/DESTINATION\ ThirdParty\/lib/DESTINATION\ lib/g' CMakeLists.txt

# Add include directories to clang++ for building RuntimeFunctions.bc and ExtensionFunctions.ast
# This fixes failures about not finding cassert, ... include files.
CXXINC1=$BUILD_PREFIX/$HOST/include/c++/7.3.0
CXXINC2=$BUILD_PREFIX/$HOST/include/c++/7.3.0/$HOST
mv QueryEngine/CMakeLists.txt QueryEngine/CMakeLists.txt-orig
echo -e "set(CXXINC1 \"-I$CXXINC1\")" > QueryEngine/CMakeLists.txt
echo -e "set(CXXINC2 \"-I$CXXINC2\")" >> QueryEngine/CMakeLists.txt
cat QueryEngine/CMakeLists.txt-orig >> QueryEngine/CMakeLists.txt
sed -i 's/ARGS\ -std=c++14/ARGS\ -std=c++14\ \${CXXINC1}\ \${CXXINC2}/g' QueryEngine/CMakeLists.txt

export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
export ZLIB_ROOT=$PREFIX
export CC=clang
export CXX=clang++
if [ $(uname) == Darwin ]; then
  # export MACOSX_DEPLOYMENT_TARGET="10.9"
  #export CXXFLAGS="-std=c++14 -D_GLIBCXX_USE_CXX11_ABI=1"
  export LibArchive_ROOT=$PREFIX
else
  # linux
  export CXXFLAGS="$CXXFLAGS -msse4.1"  # only Centos 7 requires this
  export CXXFLAGS="$CXXFLAGS -DBOOST_ERROR_CODE_HEADER_ONLY"  # it seems that conda build also defines
fi

export CMAKE_COMPILERS="-DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX"
if [ "$(basename $CXX)" == "clang++" ]; then
    export CXXFLAGS="$CXXFLAGS -I$CXXINC1 -I$CXXINC2"
fi

mkdir -p build
cd build

# TODO: change from debug to release
cmake \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DCMAKE_BUILD_TYPE=debug \
    -DMAPD_DOCS_DOWNLOAD=off \
    -DMAPD_IMMERSE_DOWNLOAD=off \
    -DENABLE_AWS_S3=off \
    -DENABLE_CUDA=off \
    -DENABLE_FOLLY=off \
    -DENABLE_JAVA_REMOTE_DEBUG=off \
    -DENABLE_PROFILER=off \
    -DENABLE_TESTS=on  \
    -DPREFER_STATIC_LIBS=off \
    $CMAKE_COMPILERS \
    -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
    ..

make -j `nproc`
make install

mkdir tmp
$PREFIX/bin/initdb tmp
make sanity_tests
rm -rf tmp

# copy initdb to mapd_initdb to avoid conflict with psql initdb
cp $PREFIX/bin/initdb $PREFIX/bin/mapd_initdb
