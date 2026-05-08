import time
import serial
# configure the serial port
ser = serial.Serial(
    port='COM3',
    baudrate=57600,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_ONE,
    bytesize=serial.EIGHTBITS
)
ser.isOpen()
while 1 :
    strin = ser.readline()
    text = strin.decode('ascii').strip()
    val = int(text)/100   
    print(val)


    