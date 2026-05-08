import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, time, math
from matplotlib.collections import LineCollection
import matplotlib.cm as cm


import serial
# configure the serial port
ser = serial.Serial(
    port='COM3',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS
)
ser.isOpen()

xsize=50
points=0

def data_gen():
    t = data_gen.t
    while True:
        t+=1
        strin = ser.readline()
        text = strin.decode('ascii').strip()
        val = int(text)/100   
        yield t, val

def run(data):
    # update the data
    t,y = data
    if t>-1:
        xdata.append(t)
        ydata.append(y)
        if t>xsize: # Scroll to the left.
            ax.set_xlim(t-xsize, t)
        
        ax.set_title(f"Temperature over Time  |  Samples: {t}")

        
        text.set_text(f"Temp: {y:.2f}")

        window = 10
        if len(ydata) >= window:
            avg = np.mean(ydata[-window:])
            std = np.std(ydata[-window:])
            stats_text.set_text(f"Avg: {avg:.2f}  σ: {std:.2f}")

        if len(xdata) > 1:
            pts = np.array([xdata, ydata]).T.reshape(-1, 1, 2)
            segs = np.concatenate([pts[:-1], pts[1:]], axis=1)

            segments.set_segments(segs)
            segments.set_array(np.array(ydata[:-1]))

            # manual y autoscale with margin
            ymin = min(ydata)
            ymax = max(ydata)
            margin = 0.2 * (ymax - ymin if ymax != ymin else 1)
            ax.set_ylim(ymin - margin, ymax + margin)

        ymin = min(ydata)
        ymax = max(ydata)

        margin = 0.2 * (ymax - ymin if ymax != ymin else 1)

        ax.set_ylim(ymin - margin, ymax + margin)
    return segments, text

def on_close_figure(event):
    sys.exit(0)

data_gen.t = -1
fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)

cmap = cm.plasma
norm = plt.Normalize(15, 50)   # expected temperature range

segments = LineCollection([], cmap=cmap, norm=norm, linewidth=2)
ax.add_collection(segments)

ax.set_ylim(5, 50)
ax.set_xlim(0, xsize)
ax.grid()
xdata, ydata = [], []
plt.xlabel("Time (200ms)")
plt.ylabel("Temperature")

plt.title("Temperature over Time")


ax.grid(True, which="both", linestyle="--", alpha=0.5)
ax.tick_params(axis='both', labelsize=10)
text = ax.text(0.0, 1.06, "", transform=ax.transAxes)
ax.margins(y=0.2)

stats_text = ax.text(0.0, 1.02, "", transform=ax.transAxes)




# Important: Although blit=True makes graphing faster, we need blit=False to prevent
# spurious lines to appear when resizing the stripchart.
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()
