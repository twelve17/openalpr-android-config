#!/bin/bash -x

# Build openalpr dependencies for various architectures and optionally 
# copy them into an existing Android Studio project.

# Usage: 
# ./bin/build_dependencies.sh [/path/to/android/studio/project/root]

# For more info, see the README here:
# https://github.com/twelve17/openalpr-android-config

trap "echo 'error with last command. exiting.' && exit 1" ERR
trap "echo 'user interrupted.' && exit 1" INT

BASE_DIR=`pwd`
ETC_DIR=$BASE_DIR/etc
WORK_DIR=$BASE_DIR/work

TARGET_PROJECT_DIR=$1

GLOBAL_OUTDIR="$WORK_DIR/output"

if [ -z $ANDROID_DEV_HOME ]; then 
  export ANDROID_DEV_HOME=$HOME/Android 
fi

ANDROID_PLATFORM=21
ANDROID_SDK_NAME="adt-bundle-mac-x86_64-20140702"
ANDROID_NDK_NAME="android-ndk-r10d"
ANDROID_OPENCV_SDK_NAME="OpenCV-2.4.10-android-sdk"

OPENALPR_REPO="git@github.com:openalpr/openalpr.git"
OPENALPR_MODULE_NAME="openalpr"
OPENALPR_BUILD_DIR="$WORK_DIR/$OPENALPR_MODULE_NAME"

# used for JNI support in openalpr
JAVA_SDK_DIR=/System/Library/Frameworks/JavaVM.framework
JAVA_SDK_LIB_DIR=$JAVA_SDK_DIR/Libraries
JAVA_SDK_INCLUDE_DIR=$JAVA_SDK_DIR/Headers

TESS_TWO_REPO="git://github.com/rmtheis/tess-two"
TESS_TWO_MODULE_NAME="tess-two"
TESS_TWO_BUILD_DIR="$WORK_DIR/$TESS_TWO_MODULE_NAME"

ANDROID_CMAKE_REPO="https://github.com/taka-no-me/android-cmake.git " # this is a fork
ANDROID_CMAKE_MODULE_NAME=android-cmake

#BUILD_ARCHS="i386 armv7 armv7s arm64 x86_64"
BUILD_ARCHS="x86 armeabi armeabi-v7a mips" # arm64-v8a x86_64

# unused: arm64 x86_64 mips64
TOOLCHAIN_ARCHS="arm x86 mips"

#-----------------------------------------------------------------------------
setenv_all() {

  if [ -z "$ANDROID_DEV_HOME" ]; then 
    echo "ANDROID_DEV_HOME not set" && exit 1
  fi

  # ANDROID_SDK
  if [ -z "$ANDROID_SDK" ]; then 
    export ANDROID_SDK=$ANDROID_DEV_HOME/$ANDROID_SDK_NAME
  fi
  if [ ! -d "$ANDROID_SDK" ]; then 
    echo "ANDROID_SDK directory does not exist: $ANDROID_SDK" && exit 1
  fi

  # ANDROID_NDK
  if [ -z "$ANDROID_NDK" ]; then 
    export ANDROID_NDK=$ANDROID_DEV_HOME/$ANDROID_NDK_NAME
  fi
  if [ ! -d "$ANDROID_NDK" ]; then 
    echo "ANDROID_NDK directory does not exist: $ANDROID_NDK" && exit 1
  fi

  # ANDROID_OPENCV_SDK (not exported)
  if [ -z "$ANDROID_OPENCV_SDK" ]; then 
    ANDROID_OPENCV_SDK=$ANDROID_DEV_HOME/$ANDROID_OPENCV_SDK_NAME
  fi
  if [ ! -d "$ANDROID_OPENCV_SDK" ]; then 
    echo "ANDROID_OPENCV_SDK directory does not exist: $ANDROID_OPENCV_SDK" && exit 1
  fi

  if [ -z "$ANDROID_CMAKE" ]; then 
    ANDROID_CMAKE=$ANDROID_DEV_HOME/$ANDROID_CMAKE_NAME
  fi
  export ANDROID_CMAKE=$ANDROID_DEV_HOME/$ANDROID_CMAKE_MODULE_NAME
  if [ ! -d "$ANDROID_CMAKE" ]; then 
    echo "ANDROID_CMAKE directory does not exist: $ANDROID_CMAKE" && exit 1
  fi

  #ANDROID_STANDALONE_TOOLCHAIN=$ANDROID_DEV_HOME/android-toolchain
  #if [ ! -d "$ANDROID_STANDALONE_TOOLCHAIN" ]; then 
  #  echo "ANDROID_STANDALONE_TOOLCHAIN directory does not exist: $ANDROID_STANDALONE_TOOLCHAIN" && exit 1
  #fi

  export ANDROID_CMAKE_TOOLCHAIN=$ANDROID_CMAKE/android.toolchain.cmake
  if [ ! -f "$ANDROID_CMAKE_TOOLCHAIN" ]; then 
    echo "ANDROID_CMAKE_TOOLCHAIN file does not exist: $ANDROID_CMAKE_TOOLCHAIN" && exit 1
  fi
}

#-----------------------------------------------------------------------------
function cleanup_global_output() {
  rm -rf $GLOBAL_OUTDIR
  mkdir $GLOBAL_OUTDIR
  mkdir $GLOBAL_OUTDIR/libs
  mkdir $GLOBAL_OUTDIR/include
  for arch in $BUILD_ARCHS; do
    mkdir $GLOBAL_OUTDIR/libs/$arch
  done
}

#-----------------------------------------------------------------------------
function build_tesseract() {
  echo "Installing tesseract"
  cd $TESS_TWO_BUILD_DIR/tess-two
  $ANDROID_NDK/ndk-build
  android update project --path .
  ant release

  for arch in $BUILD_ARCHS; do
    cp libs/$arch/* $GLOBAL_OUTDIR/libs/$arch/
  done
}

#-----------------------------------------------------------------------------
function build_openalpr() {
  echo "Installing openalpr"

  # apply patch 
  cd $OPENALPR_BUILD_DIR
  patch -N -p1 -i $ETC_DIR/openalpr_android.patch

  # copy headers where openalpr can find them
  local tesseractIncludeDir=$GLOBAL_OUTDIR/include/tesseract
  mkdir -p $tesseractIncludeDir
  find $TESS_TWO_BUILD_DIR/tess-two/jni/com_googlecode_tesseract_android/src \
    -name "*.h" \
    -exec cp {} $tesseractIncludeDir/ \;

  local buildDir=$OPENALPR_BUILD_DIR/build

  for arch in $BUILD_ARCHS; do
    cd $OPENALPR_BUILD_DIR

    if [ -d "$buildDir" ]; then 
      cd $buildDir
      rm -fr * 
      cd $OPENALPR_BUILD_DIR
    else
      mkdir $buildDir
    fi

    cd $buildDir

    cmake \
      -DCMAKE_TOOLCHAIN_FILE=$ANDROID_CMAKE_TOOLCHAIN \
      -DWITH_DAEMON=NO \
      -DCMAKE_OSX_ARCHITECTURES=$arch \
      -DANDROID_ABI=$arch \
      -DOpenCV_DIR="$ANDROID_OPENCV_SDK/sdk/native/jni" \
      -DTesseract_INCLUDE_DIRS=$tesseractIncludeDir \
      -DTesseract_INCLUDE_BASEAPI_DIR="$tesseractIncludeDir/../" \
      -DTesseract_INCLUDE_CCSTRUCT_DIR="$tesseractIncludeDir/ccstruct" \
      -DTesseract_INCLUDE_CCMAIN_DIR="$tesseractIncludeDir/ccmain" \
      -DTesseract_INCLUDE_CCUTIL_DIR="$tesseractIncludeDir/ccutil" \
      -DTesseract_LIB="$TESS_TWO_BUILD_DIR/tess-two/libs/$arch/libtess.so" \
      -DLeptonica_LIB="$TESS_TWO_BUILD_DIR/tess-two/libs/$arch/liblept.so" \
      -DJAVA_AWT_INCLUDE_PATH=$JAVA_SDK_INCLUDE_DIR \
      -DJAVA_INCLUDE_PATH2=$JAVA_SDK_INCLUDE_DIR \
      -DJAVA_AWT_LIBRARY="$JAVA_SDK_LIB_DIR/libawt.jnilib" \
      -DJAVA_JVM_LIBRARY="$JAVA_SDK_LIB_DIR/libjvm.dylib" \
      ../src/

    # remove -lpthread references
    for file in `find . -name link.txt`; do 
      echo "Removing lpthread from $file" &&  perl -pi -e 's/\-lpthread//' $file
    done

    make -j12

    #-DTesseract_DIR="$TESS_TWO_BUILD_DIR/jni" 
    #-DJNI_INCLUDE_DIR=/System/Library/Frameworks/JavaVM.framework/Headers 
    #-DJNI_LIB=/System/Library/Frameworks/JavaVM.framework/Libraries 

    # copy libs
    cp $buildDir/openalpr/libopenalpr-static.a $GLOBAL_OUTDIR/libs/$arch/
    cp $buildDir/openalpr/simpleini/libsimpleini.a $GLOBAL_OUTDIR/libs/$arch/
    cp $buildDir/openalpr/support/libsupport.a $GLOBAL_OUTDIR/libs/$arch/

    # copy headers
    rsync -av --include="*.h" --include="*/" --exclude="*" \
      $OPENALPR_BUILD_DIR/src/openalpr $GLOBAL_OUTDIR/include
  done
}

#-----------------------------------------------------------------------------
function install_to_target_project() {
  echo "Installing dependencies to target project: $TARGET_PROJECT_DIR"

  # opencv libs
  rsync -av --include="libopencv_java.so" --include="*/" --exclude="*" \
   $ANDROID_OPENCV_SDK/sdk/native/libs/ $TARGET_PROJECT_DIR/app/src/main/jniLibs/

  # tess, alpr libs
  rsync -av $GLOBAL_OUTDIR/libs/ $TARGET_PROJECT_DIR/app/src/main/jniLibs/

  # tess, alpr include
  rsync -av $GLOBAL_OUTDIR/include/ $TARGET_PROJECT_DIR/app/src/main/jni/include/
}


#-----------------------------------------------------------------------------

setenv_all
cleanup_global_output

if [ ! -d "$WORK_DIR" ]; then
  mkdir $WORK_DIR 
fi

cd $WORK_DIR

if [ ! -d "$TESS_TWO_BUILD_DIR" ]; then
  echo "Fetching tess-two."
  git clone $TESS_TWO_REPO $TESS_TWO_BUILD_DIR
fi

if [ ! -d "$ANDROID_CMAKE" ]; then
  echo "Fetching android-cmake."
  git clone $ANDROID_CMAKE_REPO $ANDROID_CMAKE
fi

if [ ! -d "$OPENALPR_BUILD_DIR" ]; then
  echo "Fetching openalpr."
  git clone $OPENALPR_REPO $OPENALPR_BUILD_DIR
fi

#install_cmake
#[ $? != 0 ] && echo "cmake-android installation failed." && exit 1

build_tesseract 
[ $? != 0 ] && echo "Tesseract installation failed." && exit 1

build_openalpr
[ $? != 0 ] && echo "openalpr installation failed." && exit 1

if [ -n "$TARGET_PROJECT_DIR" ]; then
  if [ -d "$TARGET_PROJECT_DIR" ]; then
    install_to_target_project
  else
    echo "Target project dir does not exist: ${TARGET_PROJECT_DIR}" && exit 1
  fi
fi

echo "Finished!"

#TESSERACT_HEADERS=( 
#  api/apitypes.h api/baseapi.h 
#  ccmain/pageiterator.h ccmain/mutableiterator.h ccmain/ltrresultiterator.h ccmain/resultiterator.h 
#  ccmain/thresholder.h ccstruct/publictypes.h 
#  ccutil/errcode.h ccutil/genericvector.h ccutil/helpers.h 
#  ccutil/host.h ccutil/ndminx.h ccutil/ocrclass.h 
#  ccutil/platform.h ccutil/tesscallback.h ccutil/unichar.h 
#)

##-----------------------------------------------------------------------------
#function set_env_for_openalpr() {
#
#  local arch=$1
#
#  unset ANDROID_CMAKE_TARGET
#
## ~/Android/android-cmake/android.toolchain.cmake
##      Possible targets are:
##        "armeabi" - ARMv5TE based CPU with software floating point operations
##        "armeabi-v7a" - ARMv7 based devices with hardware FPU instructions
##            this ABI target is used by default
##        "armeabi-v7a with NEON" - same as armeabi-v7a, but
##            sets NEON as floating-point unit
##        "armeabi-v7a with VFPV3" - same as armeabi-v7a, but
##            sets VFPV3 as floating-point unit (has 32 registers instead of 16)
##        "armeabi-v6 with VFP" - tuned for ARMv6 processors having VFP
##        "x86" - IA-32 instruction set
##        "mips" - MIPS32 instruction set
##
##      64-bit ABIs for NDK r10 and newer:
##        "arm64-v8a" - ARMv8 AArch64 instruction set
##        "x86_64" - Intel64 instruction set (r1)
##        "mips64" - MIPS64 instruction set (r6)
# 
#
#  if [ "$arch" == "i386" ]; then 
#    export ANDROID_CMAKE_TARGET="x86"
#  elif [ "$arch" == "x86_64" ] || [ "$arch" == "armeabi" ] || [ "$arch" == "armeabi-v7a" ] || [ "$arch" == "mips" ]; then 
#    export ANDROID_CMAKE_TARGET=$arch
#  elif [ "$arch" == "arm64" ]; then 
#    export ANDROID_CMAKE_TARGET="arm64-v8a"
#  else 
#    echo "Unknown arch: $arch"
#    exit 1
#  fi
#
##  if [ ! -f "$SDKROOT" ] &&  [ ! -h "$SDKROOT" ]; then
##    echo "SDKROOT does not exist: $SDKROOT"
##    exit 1
##  fi
##
##  setenv_all
#}

##-----------------------------------------------------------------------------
#function install_cmake() {
#  cd $WORK_DIR 
#
##  for arch in $TOOLCHAIN_ARCHS; do
##
##    local installDir="$ANDROID_DEV_HOME/android-toolchain-${arch}"
##
##    if [ -d $installDir ]; then 
##      echo "Found existing android-toolchain for $arch in $installDir"
##    else
##      $ANDROID_NDK/build/tools/make-standalone-toolchain.sh \
##        --platform=android-$ANDROID_PLATFORM \
##        --install-dir=$installDir \
##        --arch=${arch}
##      echo "make-standalone-toolchain result: $?"
##    fi
##  done
#
##  if [ -d $ANDROID_CMAKE ]; then 
##    echo "Found existing android-cmake in $ANDROID_CMAKE"
##  else
##    local installDir=`dirname $ANDROID_CMAKE`
##    cd $installDir
##    git clone $ANDROID_CMAKE_REPO
##  fi
#}


