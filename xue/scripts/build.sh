#!/usr/bin/env bash

task="debug"

if [[ $# -gt 1 ]]; then
	echo -e "\n[*] usage: build.sh [task]\n"
	exit 2
elif [[ $# -eq 1 ]]; then
	task=$1
fi

case $task in
	"clean")
		rm -r bin
		;;
	"release")
		nimble --cc:clang build --define:danger --define:noSignalHandler --gc:arc --passC:-flto --passL:-flto
		;;
	"debug")
		nimble --cc:clang build --define:debug --gc:arc
		;;
	"profiler")
		nimble --cc:clang build --define:danger --define:noSignalHandler --gc:arc --passC:-flto --passL:-flto --lineDir:on --debuginfo --debugger:native
		;;
	*)
		echo -e "\n[*] unknown task: $task\n"
		exit 2
		;;
esac
