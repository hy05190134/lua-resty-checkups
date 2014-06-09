# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;
use Cwd qw(cwd);

#repeat_each(2);

workers(4);

plan tests => repeat_each() * (blocks() * 3 + 2);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_socket_log_errors off;
    lua_package_path "$pwd/../lua-resty-lock/?.lua;$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    error_log logs/error.log debug;

    lua_shared_dict state 10m;
    lua_shared_dict mutex 1m;
    lua_shared_dict locks 1m;

    server {
        listen 12354;
        location = /status {
            return 200;
        }
    }

    server {
        listen 12355;
        location = /status {
            return 404;
        }
    }

    server {
        listen 12356;
        location = /status {
            return 503;
        }
    }

    init_by_lua '
        local config = require "config_api"
        config.global.positive_check = false
        local checkups = require "resty.checkups"
        checkups.prepare_checker(config)
    ';

};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
#no_diff();
no_long_string();

run_tests();

__DATA__

=== TEST 1: ready_ok
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            local cb = function(host, port)
                ngx.say(host .. ":" .. port)
                return 1
            end
            checkups.ready_ok("api", cb)
            checkups.ready_ok("api", cb)
            checkups.ready_ok("api", cb)
            checkups.ready_ok("api", cb)
            checkups.ready_ok("api", cb)
            checkups.ready_ok("api", cb)
        ';
    }
--- request
GET /t
--- response_body
127.0.0.1:12354
127.0.0.1:12355
127.0.0.1:12356
127.0.0.1:12354
127.0.0.1:12355
127.0.0.1:12356
--- no_error_log
[error]
[alert]
[warn]


=== TEST 2: max_acc_fails
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            local cb = function(host, port)
                ngx.say(host .. ":" .. port)
                return 1
            end
            checkups.ready_ok("api", function(host, port)
                ngx.say(host .. ":" .. port .. " " .. "ERR")
            end)
            checkups.ready_ok("api", cb)
            checkups.ready_ok("api", cb)
            checkups.ready_ok("api", cb)
        ';
    }
--- request
GET /t
--- response_body
127.0.0.1:12354 ERR
127.0.0.1:12355 ERR
127.0.0.1:12355
127.0.0.1:12356
127.0.0.1:12354
--- grep_error_log eval: qr/max acc fails reached 127.0.0.1:\d+, acc_fails:\d+/
--- grep_error_log_out
max acc fails reached 127.0.0.1:12354, acc_fails:1
max acc fails reached 127.0.0.1:12355, acc_fails:1


=== TEST 3: no server available
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        access_log off;
        content_by_lua '
            local checkups = require "resty.checkups"
            checkups.create_checker()
            local cb_ok = function(host, port)
                ngx.say(host .. ":" .. port)
                return 1
            end
            local cb_err = function(host, port)
                ngx.say(host .. ":" .. port .. " " .. "ERR")
            end

            local ok, err = checkups.ready_ok("api", cb_err)
            if err then
                ngx.say(err)
            end
            local ok, err = checkups.ready_ok("api", cb_err)
            if err then
                ngx.say(err)
            end
            local ok, err = checkups.ready_ok("api", cb_ok)
            if err then
                ngx.say(err)
            end
            local ok, err = checkups.ready_ok("api", cb_ok)
            if err then
                ngx.say(err)
            end
        ';
    }
--- request
GET /t
--- response_body
127.0.0.1:12354 ERR
127.0.0.1:12355 ERR
max try exceeded
127.0.0.1:12355 ERR
127.0.0.1:12356 ERR
max try exceeded
127.0.0.1:12356
127.0.0.1:12354
--- grep_error_log eval: qr/max acc fails reached 127.0.0.1:\d+, acc_fails:\d+/
--- grep_error_log_out
max acc fails reached 127.0.0.1:12354, acc_fails:1
max acc fails reached 127.0.0.1:12355, acc_fails:1
max acc fails reached 127.0.0.1:12355, acc_fails:2
max acc fails reached 127.0.0.1:12356, acc_fails:1
