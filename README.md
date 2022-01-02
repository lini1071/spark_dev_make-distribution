# spark_dev_make-distribution
Converted script for making distribution of Apache Spark

Please understand that maybe codes are little dizzy and not cleaned. This file is "not official"(only for my personal interest) and just converted copy of original bash script on official Apache Spark repository. You can use and modify it for your own but please do not commit this to official repository unless you're a regular contributor on the repository because this script is not assured to work fine.

Tested essential and simple cases on: Microsoft Windows 10 Pro (10.0.19044.1415), Apache Spark 3.2.0 (Source), tgz packing.

Python3 test case is scheduled.

JDK must be installed and JAVA_HOME environment variable must be set properly.
Locate this file to $SPARK_HOME/dev before calling it. Use Apache Maven 3.8.1 or older version for avoiding exception java.lang.NoSuchMethodError: org.fusesource.jansi.AnsiConsole.wrapOutputStream

Usage: .dev\make-distribution.ps1 --mvn <maven path> ...
Example : .dev\make-distribution.ps1 --mvn D:\mvn\bin\mvn.cmd
