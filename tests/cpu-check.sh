#!/bin/bash

whatCPU=$(lscpu | awk -F ':' '/^Model name/ {print $2}' | awk '{print $1}')

printf "${whatCPU}\n"
