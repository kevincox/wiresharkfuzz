#! /bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"

cloneorupdate() {
	if [ -d "$2" ]; then
		echo "Updating $2"
		(cd "$2" && git pull)
	else
		git clone "$1" "$2"
	fi
}
cloneorupdate https://github.com/kevincox/ceph-caps.git ceph-caps
cloneorupdate https://code.wireshark.org/review/wireshark wireshark

mkdir -p build/
cd build/
cmake ../wireshark \
	-DCFLAGS='--param max-gcse-memory=0 -ftrack-macro-expansion=0' \
	-DLDFLAGS='--no-keep-memory --reduce-memory-overheads' \
	-DCMAKE_BUILD_TYPE=Debug
r=$?
if [ $r != 0 ]; then echo "cmake exited with $r"; exit $r; fi
make tshark editcap capinfos VERBOSE=1
if [ $r != 0 ]; then echo "make exited with $r"; exit $r; fi
cd ..

set -o pipefail

run=1
r=0

while [ $r == 0 ]; do
	(
		cd build/run/
		echo "Starting fuzz round $runs."
		../../wireshark/tools/fuzz-test.sh -2gp 1 ../../ceph-caps/*.pcapng.gz
		exit $?
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
mutt -s 'Wireshark Fuzz Failure' -a "$cap" -- kevincox+fuzz@kevincox.ca < fuzzout.txt 
