--!strict
local host = require("./host.luau")
local compat = require("./compat.luau")
local config = require("./config.luau")
local filesystem = require("./filesystem.luau")
local lifecycle = require("./lifecycle.luau")
local log = require("./log.luau")
local proc = require("./proc.luau")
local state = require("./state.luau")
local codec = require("./codec.luau")

export type StateChannel<T> = state.StateChannel<T>
export type Logger = log.Logger
export type LogLevel = log.LogLevel

return {
	compat = compat,
	config = config,
	filesystem = filesystem,
	lifecycle = lifecycle,
	log = log,
	proc = proc,
	state = state,
	codec = codec,
	__setHost = host.setInjectedHost,
}
