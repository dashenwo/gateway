package = "rockspec"

version = "1.0-1"
source = {

  url = "git+https://github.com/dashenwo/gateway.git",

  tag = "v1.0-1",

  branch = "master"
}
description = {

   summary = "一个apisix网关的自定义开发架构",

   homepage = "https://github.com/dashenwo/gateway",

   maintainer = "liuqin<8766771120@qq.com>",

   license = "Apache License 2.0",
}

dependencies = {
  "lua-resty-redis-cluster = 1.1-0",
}
build = {
   type = "builtin",
   modules = {}
}
