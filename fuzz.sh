#! /bin/bash

ws_git=${FUZZ_WIRESHARK_GIT:-https://code.wireshark.org/review/wireshark}
ws_branch=${FUZZ_WIRESHARK_BRANCH:-master}
caps_git=${FUZZ_CAPS_GIT:-https://github.com/kevincox/ceph-caps.git}
caps_branch=${FUZZ_CAPS_BRANCH:-master}

cloneorupdate() {
	if [ \! -d "$3" ]; then
		git clone "$1" "$3"
	fi
	echo "Updating $3"
	(cd "$3" && git fetch "$1" "$2" && git reset --hard FETCH_HEAD)
}
cloneorupdate "$caps_git" "$caps_branch" caps
cloneorupdate "$ws_git" "$ws_branch" wireshark

mkdir -p build/
cd build/
cmake ../wireshark \
	-DBUILD_wireshark=OFF \
	-DBUILD_qtshark=OFF \
	-DENABLE_GTK3=OFF \
	-DENABLE_QT5=OFF \
	-DCFLAGS='--param max-gcse-memory=0 -ftrack-macro-expansion=0' \
	-DLDFLAGS='--no-keep-memory --reduce-memory-overheads' \
	-DCMAKE_BUILD_TYPE=Debug
r=$?
if [ $r != 0 ]; then echo "cmake exited with $r"; exit $r; fi
make tshark editcap capinfos VERBOSE=1
r=$?
if [ $r != 0 ]; then echo "make exited with $r"; exit $r; fi
cd ..

set -o pipefail

run=1
r=0

while [ $r == 0 ]; do
	(
		cd build/run/
		echo "Starting fuzz round $run."
		exec bash ../../wireshark/tools/fuzz-test.sh -2gp 1 ../../caps/*.pcapng.gz
	) | tee fuzzout.txt
	r=$?
	run=$(($run+1))
	
	if [ $run -ge 100 ]; then
		echo "Hurray! $run rounds of fuzzing without an error.  Quitting."
		exit 0
	fi
done

echo "Error occured: exited with status $r!" >> fuzzout.txt
cap="$(sed -ne 's/^ *Output file: *//p' fuzzout.txt)"
mutt -s 'Wireshark Fuzz Failure' -a "$cap" -- "${FUZZ_EMAIL}" < fuzzout.txt 
