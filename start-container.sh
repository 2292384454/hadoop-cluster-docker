#!/bin/bash

# the default node number is 3
N=${1:-3}

# start hadoop master container
sudo docker rm -f hadoop-master &>/dev/null
echo "start hadoop-master container..."
sudo docker run -itd \
  --net=hadoop \
  -p 50070:50070 \
  -p 8088:8088 \
  -p 9000:9000 \
  -p 2222:22 \
  --name hadoop-master \
  --hostname hadoop-master \
  -v /Users/kalyanhuang/Learning/Hadoop/haoop_the_definitive_guide:/haoop_the_definitive_guide \
  kalyanhuang/hadoop-2.10.2:v1.0 &>/dev/null

# start hadoop slave container
i=1
while [ $i -lt $N ]; do
  sudo docker rm -f hadoop-slave$i &>/dev/null
  echo "start hadoop-slave$i container..."
  sudo docker run -itd \
    --net=hadoop \
    --name hadoop-slave$i \
    --hostname hadoop-slave$i \
    kalyanhuang/hadoop-2.10.2:v1.0 &>/dev/null
  i=$(($i + 1))
done

# get into hadoop master container
sudo docker exec -it hadoop-master bash
