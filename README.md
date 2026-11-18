Estimates how long a MacBook will run on its current charge and from a full charge. Requires macOS 27 on Apple silicon and an internal battery.

## Installation

Download the app ZIP from [Releases](https://github.com/sashokey/battery-run/releases), unzip it, and move `Battery Run.app` to Applications. The app is ad-hoc signed and is not notarized.

## Usage notes

Estimates use the average drain since the latest wake or switch to battery power, whichever came later. An estimate appears after at least one percentage point and one minute of discharge. Historical start times are approximate. When the app cannot recover a forecast baseline from power history, it uses the first reading after launch.
