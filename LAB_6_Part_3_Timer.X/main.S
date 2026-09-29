    ; Luke Groesbeck
    ; RCET3373
    ; Timers
    ; https://github.com/groeluke/Lab_6_Timers-/tree/main/LAB_6_Part_2_Timer.X
    
; PIC16F883 Configuration Bit Settings

; Assembly source line config statements

; CONFIG1
  CONFIG  FOSC = XT             ; Oscillator Selection bits (XT oscillator: Crystal/resonator on RA6/OSC2/CLKOUT and RA7/OSC1/CLKIN)
  CONFIG  WDTE = OFF            ; Watchdog Timer Enable bit (WDT disabled and can be enabled by SWDTEN bit of the WDTCON register)
  CONFIG  PWRTE = OFF           ; Power-up Timer Enable bit (PWRT disabled)
  CONFIG  MCLRE = ON            ; RE3/MCLR pin function select bit (RE3/MCLR pin function is MCLR)
  CONFIG  CP = OFF              ; Code Protection bit (Program memory code protection is disabled)
  CONFIG  CPD = OFF             ; Data Code Protection bit (Data memory code protection is disabled)
  CONFIG  BOREN = OFF           ; Brown Out Reset Selection bits (BOR disabled)
  CONFIG  IESO = OFF            ; Internal External Switchover bit (Internal/External Switchover mode is disabled)
  CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor Enabled bit (Fail-Safe Clock Monitor is disabled)
  CONFIG  LVP = OFF             ; Low Voltage Programming Enable bit (RB3 pin has digital I/O, HV on MCLR must be used for programming)

; CONFIG2
  CONFIG  BOR4V = BOR40V        ; Brown-out Reset Selection bit (Brown-out Reset set to 4.0V)
  CONFIG  WRT = OFF             ; Flash Program Memory Self Write Enable bits (Write protection off)

; config statements should precede project file includes.
#include <xc.inc>
  W_TEMP              EQU 0x70   ;saved W during ISR
   STATUS_TEMP        EQU 0x71   ;saved swapped STATUS during ISR
   OLD_PORTB          EQU 0x72   ;PORTB snapshot from previous IOC event
   CURR_PORTB         EQU 0x73   ;current PORTB read, this IOC event
   RISING_BITS        EQU 0x74   ;bits that changed AND are now high
   TEMP_COUNT         EQU 0x75   ;STATE_COUNT extracted in main, this pass
   intersection_state EQU 0x76   ;the packed state byte

; Reset Vector at 0000h. Execution starts here after reset.
PSECT resetVect,class=CODE,delta=2
ResetVector: 
    GOTO Setup

; Interrupt Vector at 0004h. Execution starts here after an interrupt.
PSECT isrVect,class=CODE,delta=2
InterruptVector:
    GOTO IsrHandler
   
; Main code section starts at 0008h. User code goes here.
PSECT code,class=CODE,delta=2
 
Setup: 
    ;          Bank 1
    BANKSEL TRISB
    BSF     TRISB,0          ;set RB0 as input
    BSF     TRISB,4          ;set RB4 as N/S sensor input
    BSF     TRISB,5          ;set RB5 as E/W sensor input
    CLRF    TRISC            ;portC asll outputs for LEDs
    BANKSEL OPTION_REG
    BCF     OPTION_REG,6     ;interrupt on a falling edge on RB0/INT
    BSF     IOCB,4          ;watch RB4 for changes
    BSF     IOCB,5          ;watch RB5 for changes
    ;          Bank 3
    BANKSEL ANSEL
    CLRF    ANSEL
    CLRF    ANSELH           ;set digital I/O 
    ;          Bank 0
    BANKSEL PORTC
    CLRF    PORTC            ;clear portC outputs to a known state
    CLRF intersection_state  ;set STATE_COUNT=0, DIRECTION=0(N/S), TRANSITION=0, flags cleared
    MOVF    PORTB,W          ;set a basline PortB reading
    MOVWF   OLD_PORTB        ;reports the sensor that actually changed
    
    BCF INTCON,0             ;clear the change on PortB interrrupt flag
    BCF INTCON,1             ;clear the external interrupt flag
    BSF INTCON,3             ;enable change on PortB interrupt enable bit
    BSF INTCON,4             ;enable external interrupt enable bit
    BSF INTCON,7             ;global interrupts enable
    
Main:
    MOVF    intersection_state,W
    MOVWF   PORTC            ;display the complete packed state, every pass

    SWAPF   intersection_state,W
    ANDLW   0x0F             ;isolate STATE_COUNT into the low 4 bits
    MOVWF   TEMP_COUNT

    MOVF    TEMP_COUNT,W
    XORLW   3
    BTFSC   STATUS,2         ;set if STATE_COUNT 3
    CALL    Decide_State3

    MOVF    TEMP_COUNT,W
    XORLW   4
    BTFSC   STATUS,2         ;set if STATE_COUNT 4
    CALL    Complete_Transition
    GOTO Main

Decide_State3:
    BCF     INTCON,7              ;protect this multi-step read/write
    BTFSC   intersection_state,3  ;check if TRANSITION is already set
    GOTO    D3_Done               ;yes already changing, do nothing

    BTFSS   intersection_state,0  ;test DIRECTION
    GOTO    D3_EW_Green           ;DIRECTION=1 -> E/W green path
                                  ;DIRECTION=0 -> N/S green:
    BTFSS   intersection_state,1  ;NS_DETECTED?
    GOTO    D3_Change             ;NS not detected -> change (0,0 / 0,1 cases)
    BTFSC   intersection_state,2  ;EW_DETECTED also set?
    GOTO    D3_Change             ;both detected -> change (1,1 case)
    GOTO    D3_Remain             ;NS only -> remain (1,0 case)
    
D3_EW_Green:
    BTFSS   intersection_state,2  ;was EW_DETECTED
    GOTO    D3_Change             ;EW not detected -> change
    BTFSC   intersection_state,1  ;was NS_DETECTED also set
    GOTO    D3_Change             ;both detected -> change
    GOTO    D3_Remain             ;EW only -> remain

D3_Remain:
    MOVF    intersection_state,W
    ANDLW   0x09                  ;keep DIRECTION bit0 and TRANSITION(bit3, =0 here)
    MOVWF   intersection_state    ;clears STATE_COUNT, NS_DETECTED, EW_DETECTED
    GOTO    D3_Done

D3_Change:
    BSF     intersection_state,3  ;set TRANSITION abou to change to yellow

D3_Done:
    BSF     INTCON,7              ;turn interrupts back on
    RETURN
    
Complete_Transition:
    BCF     INTCON,7              ;protect the rewrite
    BTFSS   intersection_state,0  ;which direction was green?
    GOTO    CT_ToEW               ;was N/S - switch to E/W
    CLRF    intersection_state    ;was E/W - new state is all zero (N/S green)
    GOTO    CT_Done
CT_ToEW:
    MOVLW   0x01
    MOVWF   intersection_state    ;new state: E/W green, everything else 0
CT_Done:
    BSF     INTCON,7              ;interrupts back on
    RETURN
    
IsrHandler:
    ;         save
    MOVWF W_TEMP                  ;save W (no flags affected)
    SWAPF STATUS,W                ;STATUS into W with nibbles swapped, no flags change
    MOVWF STATUS_TEMP             ;save swapped STATUS

    ;         button caused interrupt
    BTFSC INTCON,1
    CALL  Service_INT
    
    ;         sensor change caused this
    BTFSC INTCON,0
    CALL  Service_IOC

    ;         restore 
    SWAPF STATUS_TEMP,W           ;un-swap STATUS into W
    MOVWF STATUS                  ;restores flags AND bank bits (RP0/RP1)
    SWAPF W_TEMP,F                ;swap W_TEMP nibbles in place
    SWAPF W_TEMP,W                ;swap back into W, STATUS untouched
    RETFIE
Service_INT:
    SWAPF intersection_state,W    ;STATE_COUNT into low nibble
    ADDWF intersection_state,F    ;add 0x10 which affects 7:4 and increments STATE_COUNT 0 through 15
    BCF   INTCON,1                ;clear button flag
    RETURN
    
Service_IOC:
    MOVF    PORTB,W                 ; read PORTB (clears the mismatch)
    MOVWF   CURR_PORTB
    XORWF   OLD_PORTB,W             ; W = bits that changed
    ANDWF   CURR_PORTB,W            ; W = changed AND now-high = rising edges only
    MOVWF   RISING_BITS

    BTFSC   RISING_BITS,4           ; RB4 (N/S) rose?
    BSF     intersection_state,1    ; latch NS_DETECTED

    BTFSC   RISING_BITS,5           ; RB5 (E/W) rose?
    BSF     intersection_state,2    ; latch EW_DETECTED

    MOVF    CURR_PORTB,W
    MOVWF   OLD_PORTB                ; save for next time
    BCF     INTCON,0                 ; clear sensor flag
    RETURN
    
    End
    