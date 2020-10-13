--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local core        = require("apisix.core")
local plugin_name = "session-auth"
local random       = require "resty.random"
local schema = {
    type = "object",
    properties = {
        --加密字符串
        secret={type="string",minLength=1,},
        --前缀
        name = {type="string",minimum = 1, default = "session_id"},
        --session过期事件
        expire = {type = "integer", minimum = 1,default = 3600},
        --redis请求超时事件
        timeout = {
            type = "integer", minimum = 1,
            default = 1000,
        },
        storage = {
            type = "string",
            enum = {"redis", "memcache"},
            default = "redis",
        },
        password = {type="string",minLength = 0,},
    },
    required = {"name","expire","timeout","storage"},
    dependencies = {
        storage = {
            oneOf = {
                {
                    properties = {
                        storage = {
                            enum = {"redis"},
                        },
                        mode = {
                            type = "string",
                            enum = {"single", "cluster"},
                            default = "single",
                        },
                    },
                    required = {"mode"},
                    dependencies = {
                        mode = {
                            oneOf = {
                                {
                                    properties = {
                                        mode = {
                                            enum = {"single"},
                                        },
                                        host = {
                                            type = "object",
                                            properties = {
                                                ip = {type="string"},
                                                port = {type = "integer",minimum = 1, default = 6379,}
                                            },
                                            required = {"ip","port"},
                                        },
                                    },
                                },
                                {
                                    properties = {
                                        mode = {
                                            enum = {"cluster"},
                                        },
                                        hosts = {
                                            type = "array",
                                            items = {
                                                type = "object",
                                                properties = {
                                                    ip = {type="string"},
                                                    port = {type = "integer",minimum = 1, default = 6379,}
                                                },
                                                required = {"ip","port"},
                                            },
                                            minItems = 1
                                        },
                                    },
                                }
                            }
                        }
                    }
                },
                {
                    properties = {
                        storage = {
                            enum = {"memcache"},
                        },
                        host = {
                            type = "object",
                            properties = {
                                ip = {type="string"},
                                port = {type = "integer",minimum = 1, default = 6379,}
                            },
                            required = {"ip","port"},
                        },
                    },
                },
            }
        }
    }
}
local bytes        = random.bytes
local secret = bytes(32, true) or bytes(32)

local _M = {
    version  = 0.1,
    priority = 3200,
    type = 'auth',
    name     = plugin_name,
    schema   = schema,
}
function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    return true
end

do
    function _M.rewrite(conf, ctx)
        local ses       = require("apisix.lib.session-auth")
        local redis     = require("apisix.lib.session-auth.storage.redis")
        local memcache = require("apisix.lib.session-auth.storage.memcache")
        local defaults           = {
            name           = conf.name,
            storage        = conf.storage,
            secret         = conf.secret or secret,
            cookie         = {
                persistent = true,
                httponly = false,
                path       = "/",
                lifetime   = conf.expire,
                idletime   = 0,
                maxsize    = 4000,
            }
        }
        local session = ses.new(defaults)
        --设置存储驱动的配置信息
        if conf.storage=="redis" then
            session.redis = {
                connect_timeout = 1000,
                read_timeout =1000,
                send_timeout=1000,
                pool = {
                    name = "session",
                    timeout = 1000,
                    size = 10,
                    backlog=10
                },
                cluster = {
                    name = plugin_name,
                    dict = plugin_name,
                }
            }
            if conf.mode=="cluster" then
                session.redis.cluster.nodes = conf.hosts
            else
                session.redis.host = conf.host.ip
                session.redis.port = conf.host.port
            end
            if conf.password and conf.password~="" then
                session.redis.auth = conf.password
            end
            session.storage = redis.new(session)
        elseif conf.storage=="memcache" then
            session.memcache = {
                host = conf.host.ip,
                port = conf.host.port,
                connect_timeout = 1000,
                read_timeout =1000,
                send_timeout=1000,
                pool = {
                    name        = "session",
                    timeout     = 1000,
                    size        = 10,
                    backlog     = 10,
                }
            }
            session.storage = memcache.new(session)
        end
        session = ses.start(session)
        --session.data.username="15023989265"
        core.log.error(session.data.username)
        if not session.data.username then
            return 200,{msg="用户已过期"}
        end
        session:save()
    end
end  -- do
return _M