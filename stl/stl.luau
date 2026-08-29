--!strict
local compat = require("./compat")
local config = require("./config")
local filesystem = require("./filesystem")
local lifecycle = require("./lifecycle")
local log = require("./log")
local proc = require("./proc")
local state = require("./state")
local test = require("./test")

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
	test = test,
}
