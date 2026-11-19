Estimates how long a MacBook will run on its current charge and from a full charge. Requires macOS 27 on Apple silicon and an internal battery.

## Installation

Download the app ZIP from [Releases](https://github.com/sashokey/battery-run/releases), unzip it, and move `Battery Run.app` to Applications. The app is ad-hoc signed and is not notarized.

## Usage notes

Estimates use the average drain since the latest switch to battery power, wake, or Mac startup. The app saves this starting point across launches. An estimate requires a battery reading from the event, at least one percentage point of discharge, and at least one minute of observation. A switch to battery power can be recovered from two power history readings at most one minute apart. Historical discharge start times are approximate.
