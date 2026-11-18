#!/bin/bash
# Local Gradle with the portable toolchain in C:/Users/khale/widget-tools and a 2 GB heap (7.8 GB PC, ADR-029).
export JAVA_HOME="C:/Users/khale/widget-tools/jdk-17.0.21+9"
export PATH="$JAVA_HOME/bin:/c/Users/khale/widget-tools/gradle-8.14.3/bin:$PATH"
export ANDROID_HOME="C:/Users/khale/widget-tools/sdk"
cd /d/widget/android
exec gradle --console=plain -Dorg.gradle.jvmargs="-Xmx2g -Dfile.encoding=UTF-8" -Pkotlin.compiler.execution.strategy=in-process "$@"
