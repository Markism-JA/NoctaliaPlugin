--!nocheck
-- =============================================================================
-- Noctalia Hardware Monitoring, Disk, and Diagnostic Types
-- =============================================================================

--- CPU core performance, package load, frequency, and thermal metrics.
--- Requires API level 12 or higher. First call opts into background thermal polling.
--- @since API 12
export type SystemCpu = {
	--- Aggregate CPU busy load percentage ranging from 0 to 100.
	usagePercent: number,

	--- CPU package temperature in Celsius. Nil when no thermal sensor is detected.
	tempC: number?,

	--- Average current CPU operating frequency in MHz across active cores.
	freqMhz: number?,

	--- Maximum detected hardware clock frequency ceiling in MHz.
	maxFreqMhz: number?,
}

--- Physical system RAM utilization snapshot.
--- @since API 12
export type SystemRam = {
	--- Percentage of total physical memory currently in active use (0 - 100).
	usagePercent: number,

	--- Allocated physical memory in megabytes (MiB).
	usedMb: number,

	--- Total installed physical memory capacity in megabytes (MiB).
	totalMb: number,
}

--- System swap partition/file memory usage snapshot.
--- @since API 12
export type SystemSwap = {
	--- Allocated swap storage currently consumed in megabytes (MiB).
	usedMb: number,

	--- Total configured swap capacity in megabytes (MiB).
	totalMb: number,
}

--- Dedicated GPU utilization, thermal readings, and VRAM consumption.
--- Probes are initialized upon first access and released when the plugin unloads.
--- @since API 12
export type SystemGpu = {
	--- GPU core die temperature in Celsius. Nil when no sensor or driver probe is found.
	tempC: number?,

	--- GPU core compute load percentage (0 - 100).
	usagePercent: number?,

	--- Allocated video memory currently consumed in bytes.
	vramUsedBytes: number?,

	--- Total physical video memory capacity in bytes.
	vramTotalBytes: number?,
}

--- Aggregate and per-interface network transmission throughput rates.
--- @since API 12
export type SystemNet = {
	--- Aggregate ingress throughput in bytes per second across all active network interfaces.
	rxBytesPerSec: number,

	--- Aggregate egress throughput in bytes per second across all active network interfaces.
	txBytesPerSec: number,

	--- Individual network interface throughput rates keyed by interface identifier (e.g. `"eth0"`, `"wlan0"`).
	--- @since API 16
	interfaces: { [string]: { rxBytesPerSec: number, txBytesPerSec: number } }?,
}

--- Consolidated snapshot of the host hardware monitor state.
--- Returns nil if the host `[system.monitor]` subsystem is disabled.
--- @since API 12
export type SystemStats = {
	--- Unix epoch timestamp in milliseconds when this hardware sample was taken.
	--- @since API 16
	sampledAtMs: number?,

	--- CPU utilization, frequency, and temperature snapshot.
	cpu: SystemCpu,

	--- System physical memory snapshot.
	ram: SystemRam,

	--- System virtual swap snapshot.
	swap: SystemSwap,

	--- Dedicated GPU compute and memory load metrics.
	gpu: SystemGpu,

	--- Real-time network throughput and interface bandwidth activity.
	net: SystemNet,

	--- System CPU load averages over the trailing 1, 5, and 15 minute windows.
	loadAvg: { number },
}

--- Mounted physical block-device filesystem metadata descriptor.
--- Pseudo, loop, squashfs, and boot mounts are omitted.
--- @since API 16
export type DiskMount = {
	--- Canonical filesystem mount point directory path (e.g. `"/"`, `"/home"`).
	path: string,

	--- Block device source node identifier (e.g. `"/dev/nvme0n1p2"`).
	source: string,

	--- Filesystem format identifier (e.g. `"ext4"`, `"btrfs"`, `"zfs"`).
	filesystem: string,
}

--- Storage volume capacity, allocation, and availability metrics for a polled path.
--- Polling runs continuously on the targeted mount until the plugin unloads.
--- @since API 16
export type DiskStats = {
	--- Storage space utilization percentage across the parent volume (0 - 100).
	usagePercent: number,

	--- Total storage capacity of the volume in bytes.
	totalBytes: number,

	--- Total unallocated bytes on disk (including privileged root reserves).
	freeBytes: number,

	--- Usable storage available to unprivileged user processes in bytes.
	availableBytes: number,
}
