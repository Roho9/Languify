# iPhone performance protocol (not yet executed)

Memory, CPU, energy and thermal behaviour can only be measured on a physical iPhone. None of these have been measured. This protocol makes the measurements repeatable when a device is available.

## Setup

- Record: device model, iOS version, battery health, AirPods model, app commit, build configuration (Release, `-O`).
- Brightness 50%, auto-brightness off, Low Power Mode off, Wi-Fi on, cellular off, Bluetooth on, room 20 to 24 °C, not charging, device idle for 10 minutes before each run.
- Profile with Instruments: **Allocations + VM Tracker** (memory), **Time Profiler** (CPU), **Energy Log / Power Profiler** (energy), **Thermal State** via `ProcessInfo.thermalState` logged by a debug build.

## Workloads (each 3 repetitions)

| ID | Workload | Duration |
|---|---|---|
| D1 | App open, idle on Home | 10 min |
| D2 | Listening, 60 s window, no questions | 15, 30, 60 min |
| D3 | Listening, 120 s window, one question per 2 min | 30 min |
| D4 | D3 with screen locked and AirPods connected | 30 min |
| D5 | Flashcard and quiz session | 10 min |
| D6 | Voice playback every 30 s | 10 min |

## Measurements

- Memory: footprint at idle, during listening, peak during a question, after stop (expect a drop of about one buffer). Pass: no growth after the first full window over 60 minutes.
- CPU: mean and P95 % during each state; capture-thread time per second of audio.
- Energy: Energy Impact category and Power Profiler average mW per state. Do not rely on battery percentage alone.
- Thermal: time spent in each `thermalState`; any capture failures or added question latency in `.serious`.
- Dropped audio: compare `totalFramesWritten` with elapsed time × 16,000 (logged in debug builds).

## Results template

| Workload | Device | Footprint idle / listening / peak (MB) | CPU mean / P95 (%) | Avg power (mW) | Thermal max | Dropped frames | Notes |
|---|---|---|---|---|---|---|---|
| D1 to D6 | Not measured | | | | | | |
