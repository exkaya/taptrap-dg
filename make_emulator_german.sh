#!/bin/bash

adb -s emulator-5554 root
adb -s emulator-5554 wait-for-device
adb -s emulator-5554 shell "setprop persist.sys.locale de-DE; stop; sleep 5; start"
adb -s emulator-5554 wait-for-device
adb -s emulator-5554 shell getprop persist.sys.locale