# hadoop学习第一步：借助Docker搭建hadoop集群

## 1.了解hadoop集群

### 1.1. ` hadoop`=`HDFS`+`YARN`+`MapReduce`

从`hadoop2.X`开始，hadoop的组成部分可以分为 如下三部分：

- `HDFS`：一个Hadoop的分布式文件系统，支持`NameNode`横向扩展，解决海量数据的存储。

- `YARN`：一个负责作业调度和集群资源管理的框架，解决资源任务调度。

- `MapReduce`：一个分布式运算编程框架，用来解决海量数据的计算。

一个`hadoop`集群包括`HDFS`集群和`YARN`集群，`MapReduce`是一个编程框架。

### 1.2 HDFS集群：`namenode`和`datanode`

`HDFS`集群中有两类节点：`namenode（管理节点）`和`datanode（工作节点）`：

- `namenode`管理文件系统的命名空间，它维护着**文件系统树**及**整棵树内所有的文件和目录**，这些信息以两个文件形式永久保存在本地磁盘上：命名空间镜像文件和编辑日志文件。它也记录者每个文件中**各个块所在的数据节点信息**，但它并不永久保存块的位置信息，因为这些信息会在系统启动时根据数据节点信息重建。
- `datanode`是文件系统的工作节点，他们根据需要存储并检索数据块（受客户端或`namenode`调度），并且定期向`namenode`发送它们所存储的块的列表。

### 1.3 YARN集群：`resource manager`和`node manager`

`YARN`通过两类长期运行的守护进程提供自己的核心服务：管理集群上资源使用的资源管理器`（resource manager）`、运行在集群中所有节点上且能够启动和监控及容器的节点管理器`（node manager）`。

### 1.4 hadoop集群

一个简单的hadoop集群如下：

![hadoop集群](https://image-host-1301703314.cos.ap-guangzhou.myqcloud.com/upgit/2023/02/upgit_20230227_1677500467.jpg)

## 2. 构建Docker镜像

>  本章会比较详细地记录Docker镜像构建过程，如果只是想尽快搭建起一个Hadoop集群，并不关心具体搭建细节，可以直接跳转至 [3. 搭建Hadoop集群](https://github.com/2292384454/hadoop-cluster-docker/blob/master/README.md#3%E6%90%AD%E5%BB%BAhadoop%E9%9B%86%E7%BE%A4)。

本次我将用Docker搭建如上图所示的Hadoop集群。

### 2.1下载并安装jdk和hadoop

需要注意的是版本问题，Hadoop到目前最高也只支持到Java11（Hadoop3.3以上），如果版本不正确的话是无法启动hadoop的。从 https://cwiki.apache.org/confluence/display/HADOOP/Hadoop+Java+Versions 处可以查询hadoop支持的java版本：

![image-20230217211240034](https://image-host-1301703314.cos.ap-guangzhou.myqcloud.com/upgit/2023/02/upgit_20230217_1676639560.png)

本次我选择使用`Hadoop2.10.2`和`java8`：

```dockerfile
FROM ubuntu:20.04
WORKDIR /root

# install openssh-server, openjdk, wget, vim, ping
RUN apt-get update && apt-get install -y openssh-server openjdk-8-jdk wget vim iputils-ping

# install hadoop 2.10.2
RUN wget https://dlcdn.apache.org/hadoop/common/hadoop-2.10.2/hadoop-2.10.2.tar.gz && \
    tar -xzvf hadoop-2.10.2.tar.gz && \
    mv hadoop-2.10.2 /usr/local/hadoop && \
    rm hadoop-2.10.2.tar.gz
```

设置环境变量：

```dockerfile
# set environment variable
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-arm64              # 你的jdk安装路径
ENV HADOOP_HOME=/usr/local/hadoop
ENV PATH=$PATH:/usr/local/hadoop/bin:/usr/local/hadoop/sbin  
```

### 2.2 ssh配置

`Hadoop`控制脚本（并非守护进程）依赖SSH来执行针对整个集群的操作。为了支持无缝式工作，需要允许来自集群内机器的`hdfs`用户和`yarn`用户能够无需密码即可登录，最简单的方法就是创建一个公钥/私钥对，存放在Dockerfile中，让整个集群共享该密钥对。

```dockerfile
# ssh without key
RUN ssh-keygen -t rsa -f ~/.ssh/id_rsa -P '' && \
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
```

### 2.3 创建必要的路径

```dockerfile
RUN mkdir -p ~/hdfs/namenode && \
    mkdir -p ~/hdfs/datanode && \
    mkdir $HADOOP_HOME/logs
```

### 2.4 编辑配置文件

| 文件名称                   | 格式          | 描述                                                         |
| -------------------------- | ------------- | ------------------------------------------------------------ |
| hadoop-env.sh              | Bash脚本      | 脚本中要用到的环境变量，以运行Hadoop                         |
| mapred-env.sh              | Bash脚本      | 脚本中要用到的环境变量，以运行MapReduce(覆盖hadoop-env.sh中设置的变量) |
| yarn-env.sh                | Bash脚本      | 脚本中要用到的坏境变量，以运行YARN( 覆盖hadoop-env.sh 中设置的变量） |
| core-site.xml              | Hadoop配置XML | Hadoop Core 的配置项，例如HDFS 、MapReduce 和YARN 常用的I/O 设置等 |
| hdfs-site.xml              | Hadoop配置XML | Hadoop守护进程的配置项，包括namenode 、辅助namenode 和datanode等 |
| mapred-site.xml            | Hadoop配置XML | Map Reduce 守护进程的配置项，包括作业历史服务器              |
| yarn-site.xml              | Hadoop配置XML | *YARN 守护进程的配置项，包括资源管理器、web 应*用代理服务器和节点管理器 |
| slaves                     | 纯文本        | 运行datanode 和节点管理器的机器列表（每行一个）              |
| hadoop-metrics2.properties | java属性      | 控制如何在Hadoop上发布度量的属性                             |
| log4j.properties           | java属性      | *系统日志文件、namenode 审计日志、任务JVM 进程*的任务日志的属性 |
| hadoop-policy.xml          | Hadoop配置XML | 安全模式下运行Hadoop时的访问控制列表的配置项                 |

各个文件中要设置的内容：

1. `hadoop-env.sh`

   ```sh
   export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-arm64    # 你的jdk安装路径
   ```

2. `core-site.xml`

   ```xml
   <?xml version="1.0"?>
   <configuration>
       <!-- 用于设置Hadoop的文件系统，由URI指定 -->
       <property>
           <name>fs.defaultFS</name>
           <!-- 用于指定namenode地址在hadoop-master机器上 -->
           <value>hdfs://hadoop-master:9000/</value>
       </property>
   </configuration>
   ```

3. `hdfs-site.xml`

   ```xml
   <?xml version="1.0"?>
   <configuration>
       <!-- namenode存储永久性的元数据的目录列表 -->
       <property>
           <name>dfs.namenode.name.dir</name>
           <value>file:///root/hdfs/namenode</value>
           <description>NameNode directory for namespace and transaction logs storage.</description>
       </property>
       <!-- datanode存放数据块的目录列表 -->
       <property>
           <name>dfs.datanode.data.dir</name>
           <value>file:///root/hdfs/datanode</value>
           <description>DataNode directory</description>
       </property>
       <!-- 指定HDFS副本的数量 -->
       <property>
           <name>dfs.replication</name>
           <value>2</value>
       </property>
       <!-- 是否使用数据节点主机名连接数据节点 -->
       <property>
           <name>dfs.client.use.datanode.hostname</name>
           <value>true</value>
           <description>Whether clients should use datanode hostnames when
               connecting to datanodes.
           </description>
       </property>
   </configuration>
   
   ```

4. `mapred-site.xml`

   ```xml
   <?xml version="1.0"?>
   <configuration>
       <!-- 指定MapReduce运行时框架，这里指定在yarn上，默认是local -->
       <property>
           <name>mapreduce.framework.name</name>
           <value>yarn</value>
       </property>
   </configuration>
   
   ```

5. `yarn-site.xml`

   ```xml
   <?xml version="1.0"?>
   <configuration>
       <!-- 节点管理器运行的附加服务列表 -->
       <property>
           <name>yarn.nodemanager.aux-services</name>
           <value>mapreduce_shuffle</value>
       </property>
       <!-- 使用一个内建的AuxiliairyService:org.apache.hadoop.mapred.ShuffleHandler -->
       <property>
           <name>yarn.nodemanager.aux-services.mapreduce_shuffle.class</name>
           <value>org.apache.hadoop.mapred.ShuffleHandler</value>
       </property>
       <!-- 指定Yarn集群的管理者（ResourceManager）的地址 -->
       <property>
           <name>yarn.resourcemanager.hostname</name>
           <value>hadoop-master</value>
       </property>
   </configuration>
   ```

6. `slaves`文件记录Hadoop集群所有从节点（`HDFS`的`DataNode`和`YARN`的`NodeManager`所在主机）的主机名

   ```
   hadoop-slave1
   hadoop-slave2
   ```

这些配置文件我已经准备好了，在构建镜像时COPY进去即可。

```dockerfile
COPY config/* /tmp/
```

### 2.5 分发文件，赋予.sh文件执行权限

```dockerfile
# 分发文件
RUN mv /tmp/ssh_config ~/.ssh/config && \
    mv /tmp/sshd_config /etc/ssh/ && \
    mv /tmp/hadoop-env.sh /usr/local/hadoop/etc/hadoop/hadoop-env.sh && \
    mv /tmp/hdfs-site.xml $HADOOP_HOME/etc/hadoop/hdfs-site.xml && \
    mv /tmp/core-site.xml $HADOOP_HOME/etc/hadoop/core-site.xml && \
    mv /tmp/mapred-site.xml $HADOOP_HOME/etc/hadoop/mapred-site.xml && \
    mv /tmp/yarn-site.xml $HADOOP_HOME/etc/hadoop/yarn-site.xml && \
    mv /tmp/slaves $HADOOP_HOME/etc/hadoop/slaves && \
    mv /tmp/start-hadoop.sh ~/start-hadoop.sh && \
    mv /tmp/run-wordcount.sh ~/run-wordcount.sh

# 赋予.sh文件执行权限
RUN chmod +x ~/start-hadoop.sh && \
    chmod +x ~/run-wordcount.sh && \
    chmod +x $HADOOP_HOME/sbin/start-dfs.sh && \
    chmod +x $HADOOP_HOME/sbin/start-yarn.sh
```

### 2.6 format namenode

在hadoop部署好了之后是不能马上应用的，而是对配置的文件系统进行格式化。这里的文件系统，在物理上还未存在，或者用网络磁盘来描述更加合适；还有格式化，并不是传统意义上的磁盘清理，而是一些清除与准备工作。

namemode是hdfs系统中的管理者，它负责管理文件系统的命名空间，维护文件系统的文件树以及所有的文件和目录的元数据，元数据的格式如下：

![img](https://image-host-1301703314.cos.ap-guangzhou.myqcloud.com/upgit/2023/02/upgit_20230217_1676643585.jpg)

同时为了保证操作的可靠性，还引入了操作日志，所以，namenode会持久化这些数据到本地。对于第一次使用HDFS时，需要执行-format命令才能正常使用namenode节点。

```dockerfile
# format namenode
RUN /usr/local/hadoop/bin/hdfs namenode -format
```

### 2.7 设置用户密码，启动ssh

```dockerfile
# change password
RUN echo "root:root123" | chpasswd
# start ssh
CMD [ "sh", "-c", "service ssh start; bash"]
```

### 2.8 完整Dockerfile

```dockerfile
FROM ubuntu:20.04

WORKDIR /root

# install openssh-server, openjdk and wget
RUN apt-get update && apt-get install -y openssh-server openjdk-8-jdk wget vim iputils-ping

# install hadoop 2.10.2
RUN wget https://dlcdn.apache.org/hadoop/common/hadoop-2.10.2/hadoop-2.10.2.tar.gz && \
    tar -xzvf hadoop-2.10.2.tar.gz && \
    mv hadoop-2.10.2 /usr/local/hadoop && \
    rm hadoop-2.10.2.tar.gz

# set environment variable
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-arm64
ENV HADOOP_HOME=/usr/local/hadoop 
ENV PATH=$PATH:/usr/local/hadoop/bin:/usr/local/hadoop/sbin 

# ssh without key
RUN ssh-keygen -t rsa -f ~/.ssh/id_rsa -P '' && \
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

RUN mkdir -p ~/hdfs/namenode && \
    mkdir -p ~/hdfs/datanode && \
    mkdir $HADOOP_HOME/logs

COPY config/* /tmp/

RUN mv /tmp/ssh_config ~/.ssh/config && \
    mv /tmp/sshd_config /etc/ssh/ && \
    mv /tmp/hadoop-env.sh /usr/local/hadoop/etc/hadoop/hadoop-env.sh && \
    mv /tmp/hdfs-site.xml $HADOOP_HOME/etc/hadoop/hdfs-site.xml && \
    mv /tmp/core-site.xml $HADOOP_HOME/etc/hadoop/core-site.xml && \
    mv /tmp/mapred-site.xml $HADOOP_HOME/etc/hadoop/mapred-site.xml && \
    mv /tmp/yarn-site.xml $HADOOP_HOME/etc/hadoop/yarn-site.xml && \
    mv /tmp/slaves $HADOOP_HOME/etc/hadoop/slaves && \
    mv /tmp/start-hadoop.sh ~/start-hadoop.sh && \
    mv /tmp/run-wordcount.sh ~/run-wordcount.sh

RUN chmod +x ~/start-hadoop.sh && \
    chmod +x ~/run-wordcount.sh && \
    chmod +x $HADOOP_HOME/sbin/start-dfs.sh && \
    chmod +x $HADOOP_HOME/sbin/start-yarn.sh

# format namenode
RUN /usr/local/hadoop/bin/hdfs namenode -format

# change password
RUN echo "root:password" | chpasswd

# start ssh
CMD [ "sh", "-c", "service ssh start; bash"]
```

## 3.搭建Hadoop集群

### 3.1. 拉取 Docker 镜像

```bash
sudo docker pull kalyanhuang/hadoop-2.10.2
```

### 3.2. 克隆 github 仓库

```bash
git clone https://github.com/2292384454/hadoop-cluster-docker
```

### 3.3. 使用docker网桥创建 hadoop 网络

```bash
sudo docker network create --driver=bridge hadoop
```

> 如果你的环境是 MacOS，你可能需要阅读 [install-docker-connector.md](install-docker-connector.md)并按照里面的方法安装`docker-connector`，以让你可以在宿主机中访问容器网络。

### 3.4. 启动 docker 容器

```bash
cd hadoop-cluster-docker
sudo ./start-container.sh
```

**output:**

```bash
start hadoop-master container...
start hadoop-slave1 container...
start hadoop-slave2 container...
root@hadoop-master:~# 
```

- 这一步将启动三个容器，其中一个是主节点另外两个是从节点。
- 默认工作目录是主节点的`/root`目录

### 3.5. 启动 hadoop

```bash
./start-hadoop.sh
```

### 3.6. 运行 wordcount 任务

```bash
./run-wordcount.sh
```

这是一个简单的mapreduce任务，可以用来检测是否成功启动了hadoop。

**output:**

```bash
input file1.txt:
Hello Hadoop

input file2.txt:
Hello Docker

wordcount output:
Docker    1
Hadoop    1
Hello    2
```

## 4. 自定义Hadoop集群的节点数

### 4.1. 拉取 docker 镜像并克隆 github 仓库

完成`3.1.`到`3.3.`步骤

### 4.2. 重建docker镜像

```
sudo ./resize-cluster.sh 5
```

- 输入参数`N`必须大于1。
- 这个脚本将重写 slaves文件（见 2.4 ），为你的`N`个hadoop节点命名为`hadoop-slave1`,`...`,`hadoop-slaveN`，然后用其重新构建docker镜像。

### 4.3. 启动docker容器

```
sudo ./start-container.sh 5
```

- 输入参数N应当与 4.2. 中选择的参数保持一致。

### 4.4. 启动hadoop集群

完成`3.5.` 到`3.6.` 步骤。

## 5.参考

- 原项目地址：https://github.com/kiwenlau/hadoop-cluster-docker

- Mac -docker-connector：https://github.com/wenjunxiao/mac-docker-connector


