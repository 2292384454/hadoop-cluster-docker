#!/bin/bash

echo ""

echo -e "\nbuild docker hadoop image\n"
sudo docker build -t kalyanhuang/hadoop-2.10.2:v1.0 .

echo ""