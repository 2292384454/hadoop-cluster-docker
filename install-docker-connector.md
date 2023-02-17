# 参考 [Mac宿主机访问Docker容器网络](http://bigbigben.com/2022/03/03/about-docker-for-mac/)

1.使用brew安装docker-connector

```bash
brew install wenjunxiao/brew/docker-connector
```

2.执行下面命令将docker所有 bridge 网络都添加到docker-connector路由

> 重定向写入的是安装docker-connector后生成的配置文件，原文是`/usr/local/etc/docker-connector.conf`
> ，在我的机器上是 `/opt/homebrew/etc/docker-connector.conf`

```bash
docker network ls --filter driver=bridge --format "{{.ID}}" | xargs docker network inspect --format "route {{range .IPAM.Config}}{{.Subnet}}{{end}}" >>/opt/homebrew/etc/docker-connector.conf
```

3. 使用下面命令创建`wenjunxiao/mac-docker-connecto`r容器，要求使用 host 网络并且允许 `NET_ADMIN`

```bash
docker run -it -d --restart always --net host --cap-add NET_ADMIN --name connector wenjunxiao/mac-docker-connector
```

docker-connector容器启动成功后，macOS宿主机即可访问其它容器网络
