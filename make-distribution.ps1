# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Script to create a binary distribution for easy deploys of Spark.
# The distribution directory defaults to dist/ but can be overridden below.
# The distribution contains fat (assembly) jars that include the Scala library,
# so it is completely self contained.
# It does not contain source or *.class files.

#set -o pipefail
$ErrorActionPreference = "Stop"
Set-PSDebug -Trace 1

# Figure out where the Spark framework is installed
$SPARK_HOME=$(Split-Path -Path ([System.IO.DirectoryInfo]$MyInvocation.MyCommand.Path).Parent.FullName)
$DISTDIR="$SPARK_HOME/dist"

$MAKE_TGZ=$false
$MAKE_PIP=$false
$MAKE_R=$false
$NAME="none"
#$MVN=$SPARK_HOME + "\build\mvn"

function exit_with_usage {
  Write-Host "make-distribution.ps1 - tool for making binary distributions of Spark"
  Write-Host ""
  Write-Host "usage:"
  $cl_options="[--name] [--tgz] [--pip] [--r] [--mvn <mvn-command>]"
  Write-Host "make-distribution.ps1 $cl_options <maven build options>"
  Write-Host "See Spark's \"Building Spark\" doc for correct Maven options."
  Write-Host ""
  exit 1
}

# Parse arguments
:parse_arguments while ($args) {
  switch -wildcard ($args | Select-Object -First 1) {
    "--tgz" {
      $MAKE_TGZ=$true
	  break
	}
    "--pip" {
      $MAKE_PIP=$true
	  break
    }
    "--r" {
      $MAKE_R=$true
	  break
	}
    "--mvn" {
      $MVN=$args[1]
	  $null, $args = $args
	  break
	}
    "--name" {
      $NAME=$args[1]
	  $null, $args = $args
	  break
	}
    "--help" {
      exit_with_usage
	  break
	}
    "--*" {
      Write-Host "Error: $args[0] is not supported"
      exit_with_usage
	  break
	}
    "-*" {
      break parse_arguments
	}
    default {
      Write-Host "Error: $args[0] is not supported"
      exit_with_usage
	}
  }
  $null, $args = $args
}

#if (!$env:JAVA_HOME) {
#  # Fall back on JAVA_HOME from rpm, if found
#  if [ $(command -v rpm) ] {
#    $RPM_JAVA_HOME=$(rpm -E %java_home% 2>/dev/null)
#    if [ $RPM_JAVA_HOME != %java_home% ] {
#      $JAVA_HOME=$RPM_JAVA_HOME
#      Write-Host "No JAVA_HOME set, proceeding with '$JAVA_HOME' learned from rpm"
#    }
#  }
#
#  if [ -z "$JAVA_HOME" ] {
#    if [ `command -v java` ] {
#      # If java is in /usr/bin/java, we want /usr
#      $JAVA_HOME="$(dirname $(dirname $(which java)))"
#    }
#  }
#}

if (!$env:JAVA_HOME) {
  Write-Host "Error: JAVA_HOME is not set, cannot proceed."
  exit -1
}

Get-Command -Name git -ErrorAction SilentlyContinue
if ($?) {
    $GITREV = $(git rev-parse --short HEAD 2 > $null)
    if ($GITREV) {
        $GITREVSTRING=" (git revision $GITREV)"
	}
    $GITREV = $null
}

Get-Command -Name $MVN -ErrorAction SilentlyContinue
if (!$?) {
    Write-Host "Could not locate Maven command: '$MVN'."
    Write-Host "Specify the Maven command with the --mvn flag"
    exit -1;
}

$args=[string[]]$args
$VERSION=$(&$MVN help:evaluate '-Dexpression=project.version' $args |
	Select-String -Pattern "INFO" -NotMatch |
	Select-String -Pattern "WARNING" -NotMatch |
	Select-Object -Last 1 |
	Out-String) -replace '\r\n',''
$SCALA_VERSION=$(&$MVN help:evaluate '-Dexpression=scala.binary.version' $args |
	Select-String -Pattern "INFO" -NotMatch |
	Select-String -Pattern "WARNING" -NotMatch |
	Select-Object -Last 1 |
	Out-String) -replace '\r\n',''
$SPARK_HADOOP_VERSION=$(&$MVN help:evaluate '-Dexpression=hadoop.version' $args |
	Select-String -Pattern "INFO" -NotMatch |
	Select-String -Pattern "WARNING" -NotMatch |
	Select-Object -Last 1 |
	Out-String) -replace '\r\n',''
$SPARK_HIVE=$(&$MVN help:evaluate '-Dexpression=project.activeProfiles -pl sql/hive' $args |
	Select-String -Pattern "INFO" -NotMatch |
	Select-String -Pattern "WARNING" -NotMatch |
	Select-String -Pattern "<id>hive</id>" |
	Measure-Object -Line) -replace '\r\n',''

if ($NAME -eq "none") {
  $NAME=$SPARK_HADOOP_VERSION
}

Write-Host "Spark version is $VERSION"

if ($MAKE_TGZ) {
  Write-Host "Making spark-$VERSION-bin-$NAME.tgz"
} else {
  Write-Host "Making distribution for Spark $VERSION in '$DISTDIR'..."
}

# Build uber fat JAR
Set-Location "$SPARK_HOME"

set MAVEN_OPTS="${MAVEN_OPTS:--Xmx2g -XX:ReservedCodeCacheSize=1g}"

# Store the command as an array because $MVN variable might have spaces in it.
# Normal quoting tricks don't work.
# See: http://mywiki.wooledge.org/BashFAQ/050
$BUILD_COMMAND=@($MVN, "clean", "package", "-DskipTests")
$BUILD_COMMAND+=$args

# Actually build the jar
Write-Host "`nBuilding with..."
Write-Host "$(Invoke-Command -ScriptBlock $((Get-Item function:prompt).ScriptBlock))$($BUILD_COMMAND)\n"

Write-Host $BUILD_COMMAND[1..($BUILD_COMMAND.Count - 1)]
&$BUILD_COMMAND[0] $BUILD_COMMAND[1..($BUILD_COMMAND.Count - 1)]

# Make directories
Remove-Item -Recurse -Force "$DISTDIR" -ErrorAction SilentlyContinue
New-Item -ItemType "Directory" -Path "$DISTDIR/jars" > $null
Write-Host "Spark $VERSION$GITREVSTRING built for Hadoop $SPARK_HADOOP_VERSION" > "$DISTDIR/RELEASE"
Write-Host "Build flags: $args" >> "$DISTDIR/RELEASE"

# Copy jars
Copy-Item "$SPARK_HOME/assembly/target/scala*/jars/*" "$DISTDIR/jars/"

# Only create the yarn directory if the yarn artifacts were built.

if ($(Test-Path "$SPARK_HOME/common/network-yarn/target/scala*/spark-*-yarn-shuffle.jar" -PathType Leaf)) {
  mkdir "$DISTDIR/yarn"
  Copy-Item "$SPARK_HOME/common/network-yarn/target/scala*/spark-*-yarn-shuffle.jar" "$DISTDIR/yarn"
}

# Only create and copy the dockerfiles directory if the kubernetes artifacts were built.

if ($(Test-Path "$SPARK_HOME/resource-managers/kubernetes/core/target/" -PathType Container)) {
  New-Item -ItemType "Directory" "$DISTDIR/kubernetes/" > $null
  Copy-Item -a "$SPARK_HOME/resource-managers/kubernetes/docker/src/main/dockerfiles" "$DISTDIR/kubernetes/"
  Copy-Item -a "$SPARK_HOME/resource-managers/kubernetes/integration-tests/tests" "$DISTDIR/kubernetes/"
}

# Copy examples and dependencies
New-Item -ItemType "Directory" "$DISTDIR/examples/jars" > $null
Copy-Item "$SPARK_HOME/examples/target/scala*/jars/*" "$DISTDIR/examples/jars"

# Deduplicate jars that have already been packaged as part of the main Spark dependencies.
foreach ($f in $(Get-ChildItem "$DISTDIR/examples/jars/*")) {
  if ($(Test-Path "$DISTDIR/jars/$($f.BaseName)" -PathType Leaf)) {
    Remove-Item "$DISTDIR/examples/jars/$($f.BaseName)"
  }
}

# Copy example sources (needed for python and SQL)
New-Item -ItemType "Directory" "$DISTDIR/examples/src/main" > $null
Copy-Item "$SPARK_HOME/examples/src/main" "$DISTDIR/examples/src/" -Force -Recurse

# Copy license and ASF files
if ($(Test-Path "$SPARK_HOME/LICENSE-binary")) {
  Copy-Item "$SPARK_HOME/LICENSE-binary" "$DISTDIR/LICENSE"
  Copy-Item -Recurse "$SPARK_HOME/licenses-binary" "$DISTDIR/licenses"
  Copy-Item "$SPARK_HOME/NOTICE-binary" "$DISTDIR/NOTICE"
} else {
  Write-Host "Skipping copying LICENSE files"
}

if ($(Test-Path "$SPARK_HOME/CHANGES.txt")) {
  Copy-Item "$SPARK_HOME/CHANGES.txt" "$DISTDIR"
}

# Copy data files
Copy-Item -Recurse "$SPARK_HOME/data" "$DISTDIR"

# Make pip package
if ($MAKE_PIP) {
  Write-Host "Building python distribution package"
  Push-Location "$SPARK_HOME/python" > $null
  # Delete the egg info file if it exists, this can cache older setup files.
  Remove-Item -Force pyspark.egg-info -ErrorAction SilentlyContinue
  if (!$?) { Write-Host "No existing egg info file, skipping deletion" }
  python3 setup.py sdist
  Pop-Location > $null
} else {
  Write-Host "Skipping building python distribution package"
}

# Make R package - this is used for both CRAN release and packing R layout into distribution
if ($MAKE_R) {
  Write-Host "Building R source package"
  $R_PACKAGE_VERSION=$($(Select-String "Version" "$SPARK_HOME/R/pkg/DESCRIPTION") -split " " | Select-Object -Last 1)
  Push-Location "$SPARK_HOME/R" > $null
  # Build source package and run full checks
  # Do not source the check-cran.sh - it should be run from where it is for it to set SPARK_HOME
  $NO_TESTS=1; "$SPARK_HOME/R/check-cran.sh"

  # Move R source package to match the Spark release version if the versions are not the same.
  # NOTE(shivaram): `mv` throws an error on Linux if source and destination are same file
  if ($R_PACKAGE_VERSION -ne $VERSION) {
    Move-Item -LiteralPath "$SPARK_HOME/R/SparkR_$R_PACKAGE_VERSION.tar.gz" -Destination "$SPARK_HOME/R/SparkR_$VERSION.tar.gz"
  }

  # Install source package to get it to generate vignettes rds files, etc.
  $VERSION=$VERSION; "$SPARK_HOME/R/install-source-package.sh"
  Pop-Location > $null
} else {
  Write-Host "Skipping building R source package"
}

# Copy other things
New-Item -ItemType "Directory" "$DISTDIR/conf" > $null
Copy-Item "$SPARK_HOME/conf/*.template" "$DISTDIR/conf"
Copy-Item "$SPARK_HOME/README.md" "$DISTDIR"
Copy-Item -Recurse "$SPARK_HOME/bin" "$DISTDIR"
Copy-Item -Recurse "$SPARK_HOME/python" "$DISTDIR"

# Remove the python distribution from dist/ if we built it
if ($MAKE_PIP) {
  Remove-Item -Force "$DISTDIR/python/dist/pyspark-*.tar.gz" -ErrorAction SilentlyContinue
}

Copy-Item -Recurse "$SPARK_HOME/sbin" "$DISTDIR"
# Copy SparkR if it exists
if ($(Test-Path "$SPARK_HOME/R/lib/SparkR" -PathType Container)) {
  New-Item -ItemType "Directory" -Path "$DISTDIR/R/lib" > $null
  Copy-Item -Recurse "$SPARK_HOME/R/lib/SparkR" "$DISTDIR/R/lib"
  Copy-Item "$SPARK_HOME/R/lib/sparkr.zip" "$DISTDIR/R/lib"
}

if ($MAKE_TGZ) {
  $TARDIR_NAME="spark-$($VERSION)-bin-$($NAME)"
  $TARDIR="$SPARK_HOME/$TARDIR_NAME"
  Remove-Item -Recurse -Force "$TARDIR" -ErrorAction SilentlyContinue
  Copy-Item -Recurse "$DISTDIR" "$TARDIR"
  tar czf "spark-$VERSION-bin-$NAME.tgz" -C "$SPARK_HOME" "$TARDIR_NAME"
  Remove-Item -Recurse -Force "$TARDIR"
}
