# Getting Started

## Prerequisites

- List required tools/versions here.

## Setup

```sh
# clone, install deps, configure .env
```

## Run

```sh
# start the app / run the example
```

## Tests

```text
lua test/run.lua        # any Lua 5.1+, no framework, no dependencies
resty test/run.lua      # inside the nginx-lua image itself
```

35 assertions over the pure logic: every rate-limiting algorithm including the
fixed window's boundary burst and the sliding counter that smooths it, the mirror
safety rules, bot scoring and header-order inversions, CIDR/country/ASN
precedence, and JWT parsing, claim checks, HMAC construction and `alg: none`.
`test/mock_ngx.lua` is a small stand-in for the `ngx` API the modules touch.
