    ; Luke Groesbeck
    ; RCET3373
    ; Timers
    ; https://github.com/groeluke/Lab_6_Timers-/tree/main/LAB_6_Part_4_Timer.X
    
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
   W_TEMP             EQU 0x70     ;save W during ISR
   STATUS_TEMP        EQU 0x71     ;save STATUS during ISR
   TEMP_COUNT         EQU 0x72     ;STATE_COUNT read out in main
   intersection_state EQU 0x73     ;the packed state byte
   OLD_PORTB          EQU 0x74     ;PortB memory of previous IOC 
   CURR_PORTB         EQU 0x75     ;current PortB read from IOC
   RISING_BITS        EQU 0x76     ;the bits that change to a high state
   RUN_DEBUG          EQU 0x77     ;decides what operation happens

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
    BANKSEL TRISA
    CLRF    TRISA                  ;RA0-RA5 all outputs (six traffic-light LEDs)
    BSF     TRISB,0                ;set RB0 as input
    BSF     TRISB,1                ;set RB1 as N/S sensor input
    BSF     TRISB,2                ;set RB2 as E/W sensor input
    BSF     TRISB,2                ;set RB3 as the RUN/DEBUG to switch
    CLRF    TRISC                  ;portC asll outputs for LEDs
    BANKSEL OPTION_REG
    BCF     OPTION_REG,6           ;interrupt on a falling edge on RB0/INT
    BSF     IOCB,1                 ;watch RB1 for changes
    BSF     IOCB,2                 ;watch RB2 for changes
    BSF     IOCB,3                 ;watch RB3 for changes
    BSF     PIE1,0                 ;enable Timer1 interrupt (TMR1IE)

    ;          Bank 3
    BANKSEL ANSEL
    CLRF    ANSEL                  ;RA0-RA5 digital
    CLRF    ANSELH

    ;          Bank 0
    BANKSEL PORTA
    CLRF    PORTA                  ;lights off - first main pass sets the real pattern
    CLRF    PORTC
    CLRF    intersection_state     ;count=0, N/S green, no transition, flags clear
    MOVF    PORTB,W                ;set a basline PortB reading
    MOVWF   OLD_PORTB              ;reports the sensor that actually changed

    MOVLW   0x0B                   ;
    MOVWF   TMR1H                  ;preload for a 500 ms period, high byte
    MOVLW   0xDC                   ;
    MOVWF   TMR1L                  ;preload low byte
    BCF     PIR1,0                 ;clear TMR1IF before starting

    BCF     INTCON,0               ;clear the change on PortB interrrupt flag
    BCF     INTCON,1               ;clear the external interrupt flag
    BCF     INTCON,4               ;Part 2's external INT stays off in Part 3
    BCF     INTCON,3               ;Part 2's PORTB IOC stays off in Part 3
 
    MOVLW   0b00110001             ;setup prescale 1:8,internal clock,Timer1 ON
    MOVWF   T1CON                  ;turn on the prescaler and Timer1

    BSF     INTCON,6               ;Timer1 is a peripheral interrupt
    BSF     INTCON,7               ;global interrupts enable
    
Main:
    MOVF    intersection_state,W
    MOVWF   PORTC                  ;what state of the LEDs on PortC, every pass

    CALL    Decode_Lights          ;keeps or changes based on what occurs every pass
    
    SWAPF   intersection_state,W
    ANDLW   0x0F                   ;pull STATE_COUNT into TEMP_COUNTANDLW 0x0F
                                   ;then wipes out the garbage left in the top half, leaving a
                                   ;clean 0-15 number
    MOVWF   TEMP_COUNT

    BTFSS   PORTB,3                ;
    GOTO    RUN                    ;
    
DEBUG:
    MOVF    TEMP_COUNT,W
    XORLW   3  
    BTFSC   STATUS,2               ;set if STATE_COUNT 3
    CALL    Decide_State3

    MOVF    TEMP_COUNT,W
    XORLW   4
    BTFSC   STATUS,2               ;set if STATE_COUNT 4
    CALL    Complete_Transition

RUN:
    MOVF    TEMP_COUNT,W
    XORLW   10
    BTFSC   STATUS,2               ;count is 10 which will be 5.0 s of green elapsed
    CALL    Decide                 ;after 5s we need to decide to change to yellow

    MOVF    TEMP_COUNT,W
    XORLW   12
    BTFSC   STATUS,2               ;count is 12 which will be 1.0 s of yellow elapsed
    CALL    Finish                 ;after 1s we need to decide to what direction to change

    GOTO    Main

Decide_State3:
    BCF     INTCON,7               ;disable the interrupts for read/write
    BTFSC   intersection_state,3   ;check if TRANSITION is already set
    GOTO    D3_Done                ;yes already changing, do nothing

    BTFSS   intersection_state,0   ;test DIRECTION
    GOTO    D3_EW_Green            ;DIRECTION=1 goto E/W green path
                                   ;DIRECTION=0 goto N/S green
    BTFSS   intersection_state,1   ;is NS_DETECTED
    GOTO    D3_Change              ;NS not detected goto change (0,0 / 0,1 cases)
    BTFSC   intersection_state,2   ;is EW_DETECTED also set
    GOTO    D3_Change              ;both detected goto change (1,1 case)
    GOTO    D3_Remain              ;NS only goto remain (1,0 case)
    
D3_EW_Green:
    BTFSS   intersection_state,2   ;was EW_DETECTED
    GOTO    D3_Change              ;EW not detected goto change
    BTFSC   intersection_state,1   ;was NS_DETECTED also set
    GOTO    D3_Change              ;both detected goto change
    GOTO    D3_Remain              ;EW only goto remain

D3_Remain:
    MOVF    intersection_state,W
    ANDLW   0x09                   ;keep DIRECTION bit0 and TRANSITION(bit3, =0 here)
    MOVWF   intersection_state     ;clears STATE_COUNT, NS_DETECTED, EW_DETECTED
    GOTO    D3_Done

D3_Change:
    BSF     intersection_state,3   ;set TRANSITION about to change to yellow

D3_Done:
    BSF     INTCON,7               ;turn interrupts back on
    RETURN
    
Complete_Transition:
    BCF     INTCON,7               ;protect the rewrite
    BTFSS   intersection_state,0   ;which direction was green?
    GOTO    CT_ToEW                ;was it N/S switch to E/W
    CLRF    intersection_state     ;was E/W then new state is all zero (N/S green)
    GOTO    CT_Done
CT_ToEW:
    MOVLW   0x01
    MOVWF   intersection_state     ;if new state E/W green, everything else 0
CT_Done:
    BSF     INTCON,7               ;interrupts back on
    RETURN
    
Decide:
    BCF      INTCON,7              ;Turn of the gobel interrupt to make sure operration happens
    BTFSC    intersection_state,3  ;is TRANSITION bit set low = skip
    GOTO     Done                  ;dont do anything
    BTFSS    intersection_state,0  ;look which direction is green N/S=0, E/W=1
    GOTO     NS_Green               
EW_Green:
    BTFSS    intersection_state,2  ;is E/W_DETECTED bit set high = skip
    GOTO     Change                ;if low goto change
    BTFSS    intersection_state,1  ;is N/W_DETECTED bit set high =skip
    GOTO     Remain                ;goto Remain if N/W bit is low 
    GOTO     Change                ;goto Change if N/W and E/W bits high
NS_Green:
    BTFSS    intersection_state,1  ;is N/S bit set high = skip
    GOTO     Change                ;if N/S bit low then goto change
    BTFSS    intersection_state,2  ;is E/W bit set high = skip goto change
    GOTO     Remain                ;if E/W low there is no car, N/s has traffic
Change:
    BSF      intersection_state,3  ;turn On the TRANSITION bit to switch output pattern yellow
    GOTO     Done                  
Remain:
    BTFSS    intersection_state,0  ;check DIRECTION again before we clear the register
    GOTO     NS_Remain             ;we keep N/S green
EW_Remain:
    CLRF     intersection_state    ;clear everything
    BSF      intersection_state,0  ;only select direction E/W
    GOTO     Done                  
NS_Remain:
    CLRF     intersection_state    ;clear the register for a fresh start
Done: 
    BSF      INTCON,7              ;turn on the interrupts 
    RETURN                         ;go back to main where Decide was called from
    
;Finish: runs when STATE_COUNT hits 12 - the 1 second of yellow
;is over. Swap which direction is green and reset everything.
    
Finish:
    BCF      INTCON,7              ;protect this the same way Decide does
    BTFSS    intersection_state,0  ;which way was green before this?
    GOTO     ToEW                  ;bit was 0 - was N/S, switch to E/W
    CLRF     intersection_state    ;bit was 1 - was E/W, back to N/S green, count reset to 0
    GOTO     FinishDone
ToEW:
    MOVLW   0x01
    MOVWF   intersection_state     ;now E/W green, everything else reset to 0
FinishDone:
    BSF     INTCON,7               ;interrupts back on
    RETURN

;Decode_Lights: looks at DIRECTION and TRANSITION and turns on
;the matching traffic lights on PORTA. Called every pass through
;Main so PORTA always matches the current state.
    
Decode_Lights:
    BTFSS   intersection_state,3   ;is TRANSITION (yellow flag) on?
    GOTO    Green_Phase            ;no we're in a green/red phase
    GOTO    Yellow_Phase           ;yes we're in a yellow/red phase
Green_Phase:
    BTFSS   intersection_state,0   ;which way is green?
    GOTO    Set_NSGreen            ;bit was 0 N/S green
    GOTO    Set_EWGreen            ;bit was 1 E/W green
Yellow_Phase:
    BTFSS   intersection_state,0   
    GOTO    Set_NSYellow
    GOTO    Set_EWYellow
Set_NSGreen:
    MOVLW   0x0C                   ;RA2 on (N/S green), RA3 on (E/W red)
    GOTO    Store_Lights
Set_EWGreen:
    MOVLW   0x21                   ;RA0 on (N/S red), RA5 on (E/W green)
    GOTO    Store_Lights
Set_NSYellow:
    MOVLW   0x0A                   ;RA1 on (N/S yellow), RA3 on (E/W red)
    GOTO    Store_Lights
Set_EWYellow:
    MOVLW   0x11                   ;RA0 on (N/S red), RA4 on (E/W yellow)
Store_Lights:
    MOVWF   PORTA                  ;takes moved values and then displays on the LEDs
    RETURN

; ISR - runs any time an interrupt fires. Right now the only thing
; that should be able to interrupt is Timer1.
    
IsrHandler:
    ;         save
    MOVWF W_TEMP                   ;save W (no flags affected)
    SWAPF STATUS,W                 ;STATUS into W with nibbles swapped, no flags change
    MOVWF STATUS_TEMP              ;save swapped STATUS

    ;         button caused interrupt
    BTFSC INTCON,1
    CALL  Service_INT
    
    ;         sensor change caused this
    BTFSC INTCON,0
    CALL  Service_IOC

    ;         button caused interrupt
    BTFSC PIR1,0
    CALL  Service_Timer1
    
    ;         restore 
    SWAPF STATUS_TEMP,W            ;un-swap STATUS into W
    MOVWF STATUS                   ;restores flags AND bank bits (RP0/RP1)
    SWAPF W_TEMP,F                 ;swap W_TEMP nibbles in place
    SWAPF W_TEMP,W                 ;swap back into W, STATUS untouched
    RETFIE
    
Service_INT:
    MOVLW 0x10
    ADDWF intersection_state,F    ;add 0x10 which affects 7:4 and increments STATE_COUNT 0 through 15
    BCF   INTCON,1                ;clear button flag
    RETURN
    
Service_IOC:
    MOVF    PORTB,W                 ;read PORTB (clears the mismatch)
    MOVWF   CURR_PORTB
    XORWF   OLD_PORTB,W             ;W= bits that changed
    ANDWF   CURR_PORTB,W            ;W = changed AND now-high = rising edges only
    MOVWF   RISING_BITS

    BTFSC   RISING_BITS,4           ;did RB4 (N/S) rose
    BSF     intersection_state,1    ;latch NS_DETECTED

    BTFSC   RISING_BITS,5           ;did RB5 (E/W) rose
    BSF     intersection_state,2    ;latch EW_DETECTED

    MOVF    CURR_PORTB,W
    MOVWF   OLD_PORTB               ;save for next time
    BCF     INTCON,0                ;clear sensor flag
    RETURN
    
Service_Timer1:
    BCF   PIR1,0                   ;clear Timer1 flag
    MOVLW 0x0B                     ;reload timer 1 with the 500ms count 
    MOVWF TMR1H                    ;load into the higher Timer1 bits
    MOVLW 0xDC                     ;reload timer one with the rrest of the count
    MOVWF TMR1L                    ;load into the lower Timer1 bits
    MOVLW 0x10                     ;increment the upper bits if intersection_state
    ADDWF intersection_state,F     ;add increments the upper bits
    RETURN                         ;return to ISR
    
    End
    