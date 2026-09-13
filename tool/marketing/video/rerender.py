"""Re-renders the frames of some shots of the render10 cut without wiping the rest.

    python rerender.py play mini      # then bash mux10.sh
"""
import sys
from multiprocessing import Pool

import render8 as R8
import render10 as R10


def frames_for(names):
    starts, total = R8.timeline()
    order = [n for n, _, _ in R10.SHOTS]
    out = set()
    for name in names:
        i = order.index(name)
        end = starts[i + 1] + R8.TOUT if i + 1 < len(starts) else total
        out.update(range(int(starts[i] * R10.FPS), min(int(round(total * R10.FPS)), int(end * R10.FPS) + 1)))
    return sorted(out)


if __name__ == "__main__":
    picks = frames_for(sys.argv[1:])
    with Pool(8) as p:
        p.map(R8.render_frame, picks, chunksize=8)
    print(f"re-rendered {len(picks)} frames ({picks[0]}-{picks[-1]})")
