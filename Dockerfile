FROM openresty/openresty:alpine-fat AS production-stage

RUN set -x \
    && /bin/sed -i 's,http://dl-cdn.alpinelinux.org,https://mirrors.aliyun.com,g' /etc/apk/repositories \
    && apk add --no-cache --virtual .builddeps \
    automake \
    autoconf \
    libtool \
    pkgconfig \
    cmake \
    git \
    && luarocks install https://github.com/apache/apisix/raw/master/rockspec/apisix-master-0.rockspec --tree=/usr/local/apisix/deps \
    && cp -v /usr/local/apisix/deps/lib/luarocks/rocks-5.1/apisix/master-0/bin/apisix /usr/bin/ \
    && bin='#! /usr/local/openresty/luajit/bin/luajit\npackage.path = "/usr/local/apisix/?.lua;" .. package.path' \
    && sed -i "1s@.*@$bin@" /usr/bin/apisix \
    && mv /usr/local/apisix/deps/share/lua/5.1/apisix /usr/local/apisix \
    && apk del .builddeps build-base make unzip

FROM alpine:3.11 AS last-stage

# add runtime for Apache APISIX
RUN set -x \
    && /bin/sed -i 's,http://dl-cdn.alpinelinux.org,https://mirrors.aliyun.com,g' /etc/apk/repositories \
    && apk add --no-cache bash libstdc++ curl

RUN apk add tzdata && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone \
    && apk del tzdata

WORKDIR /usr/local/apisix

COPY --from=production-stage /usr/local/openresty/ /usr/local/openresty/
COPY --from=production-stage /usr/local/apisix/ /usr/local/apisix/
COPY --from=production-stage /usr/bin/apisix /usr/bin/apisix

RUN mkdir -p lua;

COPY conf conf
COPY lua lua

# 修改apisix把自己的开发目录加入进去
RUN /bin/sed -i "s#\$prefix/deps/share/lua/5.1/?.lua;#{\*apisix_lua_home\*}/lua/?.lua;{\*apisix_lua_home\*}/lua/deps/share/lua/5.1/?.lua;\$prefix/deps/share/lua/5.1/?.lua;#g" /usr/bin/apisix
RUN /bin/sed -i "s#\$prefix/deps/lib64/lua/5.1/?.so;#{\*apisix_lua_home\*}/lua/deps/lib64/lua/5.1/?.so;{\*apisix_lua_home\*}/lua/deps/lib/lua/5.1/?.so;\$prefix/deps/lib64/lua/5.1/?.so;#g" /usr/bin/apisix
# 修改自己开发的插件需要加载的内存共享
RUN /bin/sed -i "s#for custom shared dict# for custom shared dict \n \
    lua_shared_dict session-auth        10m;\n#g" /usr/bin/apisix

ENV PATH=$PATH:/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin

EXPOSE 9080 9443

CMD ["sh", "-c", "/usr/bin/apisix init && /usr/bin/apisix init_etcd && /usr/local/openresty/bin/openresty -p /usr/local/apisix -g 'daemon off;'"]

STOPSIGNAL SIGQUIT