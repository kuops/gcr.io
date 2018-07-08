# sync gcr.io/google-containers 镜像

**build stats:**   [![Build Status](https://travis-ci.org/kuops/gcr.io.svg?branch=master)](https://travis-ci.org/kuops/gcr.io)

使用 travis cli 对多个文件进行加密

```
tar zcf conf.tar.gz  config.json  gcloud.config.json  id_rsa
travis encrypt-file $HOME/conf.tar.gz --add
```

本仓库是镜像 gcr.io/google-containers 仓库中的所有镜像，用法如下

```
#原拉取地址
docker pull gcr.io/google-containers/pause:3.0
#替换 gcr.io/google-containers 为 kuops
docker pull kuops/pause:3.0
```

