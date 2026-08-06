-- luacheck configuration.
--
-- `ngx` is the OpenResty request context: injected by nginx at runtime, so it
-- is a global luacheck cannot see. The test harness assigns to it, hence
-- `globals` rather than `read_globals`.
-- An unused `self` in a mock method is the shape of a mock, not a defect.
self = false

std = "max"
globals = {"ngx"}
