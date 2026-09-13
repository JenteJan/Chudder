"""Holds a viewport smaller than Chrome allows its window to be.

Headless Chrome will not size a window below about 500 CSS pixels wide, so the
phone shots need a device-metrics override - and an override lasts only as
long as the DevTools session that set it. Run this in the background for the
length of the phone shots, then stop it:

    python hold_viewport.py 424 918
"""
import sys
import time

import web

width, height = int(sys.argv[1]), int(sys.argv[2])
cdp = web.Cdp()
cdp.call("Emulation.setDeviceMetricsOverride", width=width, height=height, deviceScaleFactor=web.SCALE, mobile=True)
cdp.call("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
print(f"holding {width}x{height}", flush=True)
while True:
    time.sleep(20)
    cdp.eval("1")  # keeps the connection alive
