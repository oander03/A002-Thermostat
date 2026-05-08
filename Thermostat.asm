; 76E003 ADC test program: Reads channel 7 on P1.1, pin 14

$NOLIST
$MODN76E003
$LIST

;  N76E003 pinout:
;                               -------
;       PWM2/IC6/T0/AIN4/P0.5 -|1    20|- P0.4/AIN5/STADC/PWM3/IC3
;               TXD/AIN3/P0.6 -|2    19|- P0.3/PWM5/IC5/AIN6
;               RXD/AIN2/P0.7 -|3    18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
;                    RST/P2.0 -|4    17|- P0.1/PWM4/IC4/MISO
;        INT0/OSCIN/AIN1/P3.0 -|5    16|- P0.0/PWM3/IC3/MOSI/T1
;              INT1/AIN0/P1.7 -|6    15|- P1.0/PWM2/IC2/SPCLK
;                         GND -|7    14|- P1.1/PWM1/IC1/AIN7/CLO
;[SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8    13|- P1.2/PWM0/IC0
;                         VDD -|9    12|- P1.3/SCL/[STADC]
;            PWM5/IC7/SS/P1.5 -|10   11|- P1.4/SDA/FB/PWM1
;                               -------
;

CLK               EQU 16600000 ; Microcontroller system frequency in Hz
BAUD              EQU 115200 ; Baud rate of UART in bps
TIMER1_RELOAD     EQU (0x100-(CLK/(16*BAUD)))
TIMER0_RELOAD_1MS EQU (0x10000-(CLK/1000))
TIMER2_RATE   	  EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD 	  EQU ((65536-(CLK/TIMER2_RATE)))

TEMP_BUTTON  	  equ P0.5
EDIT_BUTTON  	  equ P3.0
RESET_BUTTON      equ P1.5
UP_BUTTON     	  equ P1.7
DOWN_BUTTON   	  equ P1.6

ORG 0x0000
	ljmp main
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

;                     1234567890123456    <- This helps determine the location of the counter
Temp_message:    db 'Temp', 0
Celc_message:    db 'Celc    ', 0
Kelv_message:    db 'Kelv    ', 0
Fahr_message:    db 'Fahr    ', 0
Clear_message:    db '                ', 0





cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P1.3
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E  equ P1.4
LCD_D4 equ P0.0
LCD_D5 equ P0.1
LCD_D6 equ P0.2
LCD_D7 equ P0.3

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

; These register definitions needed by 'math32.inc'
DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5
tempType: ds 1
editType: ds 1
hundredsEdit: ds 1
minutesEdit: ds 1
secondsEdit: ds 1
Count1ms: ds 2

BSEG
mf: dbit 1
second_flag: dbit 1

$NOLIST
$include(math32.inc)
$LIST

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	orl T2MOD, #0x80 ; Enable timer 2 autoreload
	mov RCMP2H, #high(TIMER2_RELOAD)
	mov RCMP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
	orl EIE, #0x80 ; Enable timer 2 interrupt ET2=1
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in the ISR.  It is bit addressable.
	cpl P0.4 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(300), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(300), Timer2_ISR_done
	
	; 1 second have passed.  Set a flag so the main program knows
	setb second_flag ; Let the main program know half second had passed
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti

Init_All:
	; Configure all the pins for biderectional I/O
	mov	P3M1, #0x00
	mov	P3M2, #0x00
	mov	P1M1, #0x00
	mov	P1M2, #0x00
	mov	P0M1, #0x00
	mov	P0M2, #0x00
	
	orl	CKCON, #0x10 ; CLK is the input for timer 1
	orl	PCON, #0x80 ; Bit SMOD=1, double baud rate
	mov	SCON, #0x52
	anl	T3CON, #0b11011111
	anl	TMOD, #0x0F ; Clear the configuration bits for timer 1
	orl	TMOD, #0x20 ; Timer 1 Mode 2
	mov	TH1, #TIMER1_RELOAD ; TH1=TIMER1_RELOAD;
	setb TR1
	
	; Using timer 0 for delay functions.  Initialize here:
	clr	TR0 ; Stop timer 0
	orl	CKCON,#0x08 ; CLK is the input for timer 0
	anl	TMOD,#0xF0 ; Clear the configuration bits for timer 0
	orl	TMOD,#0x01 ; Timer 0 in Mode 1: 16-bit timer
	
	; Initialize the pin used by the ADC (P1.1) as input.
	orl	P1M1, #0b00000010
	anl	P1M2, #0b11111101
	
	; Initialize and start the ADC:
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x07 ; Select channel 7
	; AINDIDS select if some pins are analog inputs or digital I/O:
	mov AINDIDS, #0x00 ; Disable all analog inputs
	orl AINDIDS, #0b10000000 ; P1.1 is analog input
	orl ADCCON1, #0x01 ; Enable ADC
	
	;full custom character #0
	WriteCommand(#0x40)
	
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	
	;arrow custom character #1
	WriteCommand(#0x48)
	
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00100B)
	WriteData(#00010B)
	WriteData(#11111B)
	WriteData(#00010B)
	WriteData(#00100B)
	WriteData(#00000B)
	
	ret
	
wait_1ms:
	clr	TR0 ; Stop timer 0
	clr	TF0 ; Clear overflow flag
	mov	TH0, #high(TIMER0_RELOAD_1MS)
	mov	TL0,#low(TIMER0_RELOAD_1MS)
	setb TR0
	jnb	TF0, $ ; Wait for overflow
	ret

; Wait the number of miliseconds in R2
waitms:
	lcall wait_1ms
	djnz R2, waitms
	ret
	
; print to python
putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret	
	
Send2DigitBCD:
    mov R0, a

    anl a, #0F0H        ; upper
    swap a
    add a, #'0'
    lcall putchar

    mov a, R0
    anl a, #0FH         ; lower
    add a, #'0'
    lcall putchar

    ret

; We can display a number any way we want.  In this case with
; four decimal places.
Display_formated_BCD:
	clr a
	mov a, bcd+3
	cjne a, #0x00, Display_Hundreds
	
	sjmp Dont_Display_Hundreds
	
	Display_Hundreds:
	Set_Cursor(1, 10)
	Display_BCD(bcd+3)
	Set_Cursor(1, 10)
	Display_char(#' ')
	
	sjmp Display_Hundreds_2
	
	Dont_Display_Hundreds:
	Set_Cursor(1, 11)
	Display_char(#' ')
	
	Display_Hundreds_2:
	Set_Cursor(1, 12)
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Set_Cursor(1, 10)
	ret
	
main:
	mov sp, #0x7f
	lcall Init_All
    lcall LCD_4BIT
    lcall Timer2_Init
    setb EA   ; Enable Global interrupts

    mov tempType, #0x00
	mov editType, #0x00
	mov hundredsEdit, #0x01
	mov minutesEdit, #20
	mov secondsEdit, #20	
	mov bcd+3, #0x00
		
	Set_Cursor(1, 1)
    mov a, #01h
	
	animation_loop_start:
	    cjne a, #22h, animation_loop
	    sjmp animation_loop_done
	
	animation_loop:
	
		cjne a, #11h, animation_loop_continue
			Set_Cursor(2, 1)
		
		animation_loop_continue:
	    Display_char(#0)
	    mov R2, #25
		lcall waitms
	
	    inc a
	    sjmp animation_loop_start
	
	animation_loop_done:
		
	clr a 
	
	Set_Cursor(1, 1)
    Send_Constant_String(#Clear_Message)
    Set_Cursor(2, 1)
    Send_Constant_String(#Clear_Message)
	    
	; initial messages in LCD
	Set_Cursor(1, 1)
    Send_Constant_String(#Temp_message)
	Set_Cursor(2, 1)
    Send_Constant_String(#Celc_message)
    
	
Forever:


	;Reset Button -----------------------------------
	
	jb RESET_BUTTON, reset_button_check
    mov R2, #50
	lcall waitms
	jb RESET_BUTTON, reset_button_check
	jnb RESET_BUTTON, $

		mov tempType, #0x00
		mov editType, #0x00
		mov hundredsEdit, #0x01
		mov minutesEdit, #20
		mov secondsEdit, #20
		Set_Cursor(1, 9)
		Display_char(#' ')
		
	reset_button_check:

	;Temp Type Button -------------------------------------------------------------
    
    jb TEMP_BUTTON, temptype_button
    mov R2, #50
	lcall waitms
	jb TEMP_BUTTON, temptype_button
	jnb TEMP_BUTTON, $
	
		mov a, tempType
		inc a
		
		cjne a, #0x03, tempType_continue
		clr a
		tempType_continue:
		mov tempType, a
		
		
		setb second_flag
		
	
	temptype_button:
    
    mov a, tempType
    cjne a, #0x00, Celc_end
    
	    Set_Cursor(2, 1)
	    Send_Constant_String(#Celc_message)
    
    Celc_end:
    
    mov a, tempType
    cjne a, #0x01, Kelv_end
    
	    Set_Cursor(2, 1)
	    Send_Constant_String(#Kelv_message)
    
    Kelv_end:
    
    mov a, tempType
    cjne a, #0x02, Fahr_end
    
	    Set_Cursor(2, 1)
	    Send_Constant_String(#Fahr_message)
    
    Fahr_end:
    
    ; Edit Button start ---------------------------------------------------
    
	jb EDIT_BUTTON, continue_edit_1
	sjmp continue_edit_1_1
	continue_edit_1:
	ljmp edit_button_check
	continue_edit_1_1:
	mov R2, #50
	lcall waitms
	jb EDIT_BUTTON, continue_edit_2
	sjmp continue_edit_2_1
	continue_edit_2:
	ljmp edit_button_check
	continue_edit_2_1:
	jnb EDIT_BUTTON, $
	
		mov a, editType
		inc a
		
		Set_Cursor(1, 9)
		Display_char(#1)
		
		
		cjne a, #0x01, hundreds_blink
			Set_Cursor(1, 11)
			Display_char(#0)
			mov R2, #200
			lcall waitms
		hundreds_blink:
		
		cjne a, #0x02, minutes_blink
			Set_Cursor(1, 12)
			Display_char(#0)
			mov R2, #200
			lcall waitms
		minutes_blink:
		
		cjne a, #0x03, seconds_blink
			Set_Cursor(1, 13)
			Display_char(#0)
			mov R2, #200
			lcall waitms
		seconds_blink:
		
		cjne a, #0x04, editType_continue
			clr a
			Set_Cursor(1, 9)
			Display_char(#' ')
		editType_continue:
		mov editType, a
	
	edit_button_check:
	
		
	jb UP_BUTTON, continue_up_1
	sjmp continue_up_1_1
	continue_up_1:
	ljmp up_button_check
	continue_up_1_1:
	mov R2, #50
	lcall waitms
	jb UP_BUTTON, continue_up_2
	sjmp continue_up_2_1
	continue_up_2:
	ljmp up_button_check
	continue_up_2_1:
	jnb UP_BUTTON, $
	
		setb second_flag
		
		mov a, editType
		
		cjne a, #0x01, hundreds_end
		
			mov a, hundredsEdit
			inc a
			cjne a, #11, hundreds_continue
			mov a, #1
			hundreds_continue:
			mov hundredsEdit, a
		
		hundreds_end:
		
		mov a, editType
		
		cjne a, #0x02, minutes_end
		
			mov a, minutesEdit
			inc a
			cjne a, #127, minutes_continue
			clr a
			minutes_continue:
			mov minutesEdit, a
		
		minutes_end:
		
		cjne a, #0x03, seconds_end
		
			mov a, secondsEdit
			inc a
			cjne a, #127, seconds_continue
			clr a
			seconds_continue:
			mov secondsEdit, a
		
		seconds_end:
		
	up_button_check:
	
		
	jb DOWN_BUTTON, continue_down_1
	sjmp continue_down_1_1
	continue_down_1:
	ljmp down_button_check
	continue_down_1_1:
	mov R2, #50
	lcall waitms
	jb DOWN_BUTTON, continue_down_2
	sjmp continue_down_2_1
	continue_down_2:
	ljmp down_button_check
	continue_down_2_1:
	jnb DOWN_BUTTON, $
	
		setb second_flag
		
		mov a, editType
		
		cjne a, #0x01, hundreds_end_2
		
			mov a, hundredsEdit
			subb a, #1
			cjne a, #0, hundreds_continue_2
			mov a, #10
			hundreds_continue_2:
			mov hundredsEdit, a
		
		hundreds_end_2:
		
		mov a, editType
		
		cjne a, #0x02, minutes_end_2
		
			mov a, minutesEdit
			subb a, #1
			cjne a, #0, minutes_continue_2
			mov a, #20
			minutes_continue_2:
			mov minutesEdit, a
		
		minutes_end_2:
		
		cjne a, #0x03, seconds_end_2
		
			mov a, secondsEdit
			subb a, #1
			cjne a, #0, seconds_continue_2
			mov a, #20
			seconds_continue_2:
			mov secondsEdit, a
		
		seconds_end_2:
		
	down_button_check:	
    
    
    
    jb second_flag, showTemp ; Start of flag check -----------------------------------------------------------------
    
    ljmp Forever
    
    showTemp:
    
    clr ADCF
	setb ADCS ;  ADC start trigger signal
    jnb ADCF, $ ; Wait for conversion complete
    
    ; Read the ADC result and store in [R1, R0]
    mov a, ADCRH   
    swap a
    push acc
    anl a, #0x0f
    mov R1, a
    pop acc
    anl a, #0xf0
    orl a, ADCRL
    mov R0, A
    
    ; Convert to voltage
	mov x+0, R0
	mov x+1, R1
	mov x+2, #0
	mov x+3, #0
	Load_y(50300) ; VCC voltage measured
	lcall mul32
	Load_y(4095) ; 2^12-1
	lcall div32
	Load_y(28500)
	lcall sub32
	Load_y(100)
	lcall mul32
    
    
    ; edit type check --------------------------------------------------
    
    Load_y(1000000)
	lcall sub32
    
    clr a
    hundreds_repeat:
    cjne a, hundredsEdit, hundreds_change
	
		sjmp hundreds_change_end
	hundreds_change:
		
			Load_y(1000000)
			lcall add32
			inc a
		
		sjmp hundreds_repeat
	hundreds_change_end:
	
	
	Load_y(2000000)
	lcall sub32
	
	clr a
    minutes_repeat:
    cjne a, minutesEdit, minutes_change
	
		sjmp minutes_change_end
	minutes_change:
		
			Load_y(100000)
			lcall add32
			inc a
		
		sjmp minutes_repeat
	minutes_change_end:
	
	Load_y(200000)
	lcall sub32
	
	clr a
    seconds_repeat:
    cjne a, secondsEdit, seconds_change
	
		sjmp seconds_change_end
	seconds_change:
		
			Load_y(10000)
			lcall add32
			inc a
		
		sjmp seconds_repeat
	seconds_change_end:
	
; temp type check --------------------------------------------------

	mov a, tempType
    cjne a, #0x01, Kelv_end2
    
    	Load_y(2731500)
    	lcall add32
    	
    Kelv_end2:
    
    mov a, tempType
    cjne a, #0x02, Fahr_end2
    
	    Load_y(9)
	    lcall mul32
	    Load_y(5)
	    lcall div32
	    Load_y(320000)
	    lcall add32
    
    Fahr_end2:
    
    
    mov a, bcd+3
    lcall Send2DigitBCD
    mov a, bcd+2
    lcall Send2DigitBCD
    mov a, bcd+1
    lcall Send2DigitBCD
    
    mov a, #'\r'
    lcall putchar
		
	mov a, #'\n'
    lcall putchar
	
	; Convert to BCD and display
	lcall hex2bcd
	lcall Display_formated_BCD
	
	clr second_flag
	
	ljmp Forever
	
END
	