    ; Luke Groesbeck
    ; RCET3373
    ; Timers
    ; https://github.com/groeluke/Lab_6_Timers-/tree/main/LAB_6_Part_1_Timer.X
    
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
   W_TEMP      EQU 0x70 ;use data memory address 0x70 will hold W during the ISR  
   STATUS_TEMP EQU 0x71 ;use data memory address 0x71 holds swapped STATUS during the ISR

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
    BCF     TRISA,0     ;Set RA0 as output for main loop 
    BCF     TRISA,1     ;Set RA1 as output for timer diagnostic
    MOVLW   249         ;PR2 = 249 counts on Timer match
    MOVWF   PR2
    BSF     PIE1,1      ;enable Timer2 to PR2 match interrupt enable
    
    ;          Bank 3
    BANKSEL ANSEL
    CLRF    ANSEL
    CLRF    ANSELH

    ;          Bank 0
    BANKSEL PORTA
    CLRF    PORTA       ;monitor pin starts low
    CLRF    TMR2        ;Timer2 count starts at 0
    BCF     PIR1,1      ;Clear Timer2 interrupt flag
    
    BSF INTCON,6        ;enable peripheral 
    BSF INTCON,7        ;global enable
    
    MOVLW   0b00100111  ;Turn on postscarle 1:5, Timer2 On, prescale 1:16
    MOVWF   T2CON       ;


Main:
    MOVLW 0x01          ;Loads RA0 to toggle
    XORWF PORTA,1       ;toggle RA0 
    GOTO Main

IsrHandler:
    ;         save
    MOVWF W_TEMP          ;save W (no flags affected)
    SWAPF STATUS,W        ;STATUS into W with nibbles swapped, no flags change
    MOVWF STATUS_TEMP     ;save swapped STATUS

    ;         only reset Timer2
    BANKSEL PIR1
    BCF PIR1,1            ;clear Timer2 to PR2 interrupt flag
    BSF PORTA,1           ;have timer diagnostic pulse high
    BCF PORTA,1           ;set timer diagnostic pulse low


ISR_Exit:
    ;         restore 
    SWAPF STATUS_TEMP,W   ;un-swap STATUS into W
    MOVWF STATUS          ;restores flags AND bank bits (RP0/RP1)
    SWAPF W_TEMP,F        ;swap W_TEMP nibbles in place
    SWAPF W_TEMP,W        ;swap back into W, STATUS untouched
    RETFIE

    End
    