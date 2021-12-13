#!/bin/bash -e

if [[ "$(uname -s)" =~ ^CYGWIN || "$(uname -s)" =~ ^MINGW || "$(uname -s)" =~ ^MSYS ]]; then
	echo "WARNING: Building Ears on Windows, even under a Linux-like environment, is not supported. Continue at your own peril."
	sleep 3
fi

if [[ -z "$JAVA8_HOME" || -z "$JAVA11_HOME" || -z "$JAVA17_HOME" ]]; then
	echo "Building Ears requires Java 8, Java 11, and Java 17." 1>&2
	echo "Please install them and set the JAVA8_HOME, JAVA11_HOME, and JAVA17_HOME env vars." 1>&2
	echo "You can get all three of these from https://adoptium.net/" 1>&2
	exit 1
fi

if [ -n "$JAVA11_HOME" ]; then
	export JAVA_HOME=$JAVA11_HOME
fi
if [ -z "$JAVA16_HOME" ]; then
	export JAVA16_HOME=$JAVA17_HOME
fi

check_java() {
	v=$(env -u_JAVA_OPTIONS $JAVA_HOME/bin/java -Xint -version 2>&1 | head -n1 |cut -d\" -f2)
	query=$1
	regex=$2
	if [ -n "$3" ]; then
		query="$2 or $3"
		regex="$2|$3"
	fi
	highlighted=$(echo $v |grep -E --color=always "^($regex)" || (echo "Expected JAVA$1_HOME to point to Java $query, but instead it points at Java $v. Stop" 1>&2 && exit 2))
	color=32
	if [ -n "$3" ]; then
		echo $v |grep -q "^$3" >/dev/null && color=33
	fi
	highlighted=$(echo $highlighted |sed "s/31/$color/")
	echo "Java $1: $highlighted"
}

JAVA_HOME=$JAVA8_HOME check_java 8 1.8
check_java 11 11
JAVA_HOME=$JAVA16_HOME check_java 16 16 17
JAVA_HOME=$JAVA17_HOME check_java 17 17
echo "Looks good."
echo

normal="fabric-1.8 fabric-1.14 fabric-1.16 forge-1.12 forge-1.14 forge-1.15 forge-1.16 fabric-b1.7.3 rift-1.13"
needsJ8="forge-1.6 forge-1.7 forge-1.8 forge-1.9"
needsJ16="fabric-1.17 forge-1.17"
needsJ17="forge-1.18"
# these ones can't be built in parallel (or build so quickly that we shouldn't bother)
special="nfc nsss forge-1.2 forge-1.4 forge-1.5"

toBuild=" $normal $needsJ8 $needsJ16 $needsJ17 $special "
if [ -n "$1" ]; then
	toBuild=" $@ "
fi

for proj in $toBuild; do
	rm -f artifacts/ears-$proj*
done
(
	echo 'Building common...'
	cd common
	JAVA_HOME=$JAVA8_HOME TERM=dumb chronic ./gradlew clean build closure --stacktrace
)
build() {
	for proj in $@; do
		if echo "$toBuild" | grep -qF "$proj"; then
			(
				cd platform-$proj
				rm -f build-ok
				TERM=dumb chronic ./gradlew clean build --stacktrace && touch build-ok
				rm -f build/libs/*-dev.jar
			) &
		fi
	done
}
count=0
for proj in $toBuild; do
	count=$(expr $count + 1)
done
s=s
if [ $count -eq 1 ]; then
	s=
fi
echo "Building $count platform$s..."
build $normal
build $nobodyCares
JAVA_HOME=$JAVA8_HOME build $needsJ8
JAVA_HOME=$JAVA16_HOME build $needsJ16
JAVA_HOME=$JAVA17_HOME build $needsJ17
wait
for proj in $special; do
	(
		cd platform-$proj
		rm -f build-ok
		TERM=dumb chronic ./gradlew clean build --stacktrace && touch build-ok
	)
done
exit=
for proj in $toBuild; do
	if [ ! -e "platform-$proj/build-ok" ]; then
		echo "Build failure in platform $proj."
		exit=y
	fi
	rm -f "platform-$proj/build-ok"
done
if [ "$exit" == "y" ]; then
	echo "Exiting due to build failures."
	exit 1
fi
echo 'All builds completed successfully.'
mkdir -p artifacts
for proj in $toBuild; do
	cp platform-$proj/build/libs/* artifacts
done
rm -f artifacts/*-dev.jar artifacts/*-sources.jar
