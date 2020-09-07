*-----------------------------------------------------------
* Title	     : Tiny68k monitor
* Written by : A J Le Couteur Bisson
* Date	     : 31 Aug 2020
* Description:
*-----------------------------------------------------------
                OPT     MEX


*********************************
* 68681 Duart Register Addresses
*********************************
DUART		EQU	$FFF000			; Base Addr of DUART
MRA		EQU	$1			; Mode Register A		(R/W)
SRA		EQU	$3			; Status Register A		(R)
CSRA		EQU	$3			; Clock Select Register A	(W)
CRA		EQU	$5			; Commands Register A		(W)
RBA		EQU	$7			; Receiver Buffer A		(R)
TBA		EQU	$7			; Transmitter Buffer A		(W)
ACR		EQU	$9			; Aux. Control Register		(R/W)
ISR		EQU	$B			; Interrupt Status Register	(R)
IMR		EQU	$B			; Interrupt Mask Register	(W)
MRB		EQU	$11			; Mode Register B		(R/W)
SRB		EQU	$13			; Status Register B		(R)
CSRB		EQU	$13			; Clock Select Register B	(W)
CRB		EQU	$15			; Commands Register B		(W)
RBB		EQU	$17			; Reciever Buffer B		(R)
TBB		EQU	$17			; Transmitter Buffer B		(W)
IVR		EQU	$19			; Interrupt Vector Register	(R/W)
SOPB		EQU	$1D			; Set Output Port Bits Register (W)
COPB            EQU     $1F                     ; Clr Output Port Bits Register (W)

*START		EQU	$400
*RAMEND		EQU	$FF8000
*DATA		EQU	RAMEND - $1000			; Monitor data area
*STACK		EQU	DATA - 2
*VECTORS	EQU	$0

* Development config


RAMEND		EQU	$400000
STACK		EQU	RAMEND-2
USERSTACK       EQU     STACK-$400
VECTORS		EQU	$8000
DATA		EQU	VECTORS+$400
START		EQU	DATA+$400



*********************************
* Vectors
*********************************
		ORG	VECTORS

		DC.L	STACK			* Supervisor stack at the top of RAM
		DC.L	START			* Start address of monitor
		DC.L	BUSERR			* BERR handler
		DC.L	ADDRERR			* Address error handler
		DC.L	ILLEGAL			* Illegal instruction handler also implements breakpoints
		DCB.L	4,UNKNOWN
		DC.L	TRACE			* Trace handling
		DCB.L	33,UNKNOWN
		DC.L    TRAP11
		DCB.L	3,UNKNOWN
		DC.L	TRAP15			* Trap 15 implementing EASy68K trap services
		DCB.L	208,UNKNOWN

		ORG DATA

; User register storage
USERD0		DS.L	1
USERD1		DS.L	1
USERD2		DS.L	1
USERD3		DS.L	1
USERD4		DS.L	1
USERD5		DS.L	1
USERD6		DS.L	1
USERD7		DS.L	1

USERA0		DS.L	1
USERA1		DS.L	1
USERA2		DS.L	1
USERA3		DS.L	1
USERA4		DS.L	1
USERA5		DS.L	1
USERA6		DS.L	1
USERA7
USERSP          DS.L	1

USERPC		DS.L	1
USERSR		DS.W	1


BKPTS           DS.L    8                       ; Breakpoint addresses (0 if not set)
BKPTINS         DS.W    8                       ; Swapped out instruction at breakpoint address
BKPTSON         DC.B    1                       ; Set if breakpoints are installed

ERROR		DS.B	1                       ; Error code for monitor commands
M68010          DS.B    1                       ; Set if 68010 processor

                DS.W    0
LA2427   	DS.B 	1			* head
LA1623   	DS.B 	1			* cylinder high
LA815    	DS.B 	1			* cylinder low
LA07     	DS.B 	1			* sector

                DS.W    0

INBUFSZ		EQU	80                      ; User input buffer
INBUF		DS.B	INBUFSZ+2

CURRENT         DS.L    1                       ; Current address for commands

DATAEND         DS.W    0

BKPT0           EQU     $4848                   ; BKPT #0 instruction


BKSP		EQU	$08
TAB		EQU	$09
LF		EQU	$0A
CR		EQU	$0D
CTRLX		EQU	$18
ESC		EQU	$1B
SPACE		EQU	$20
DELETE		EQU	$7F

BADNUM          EQU     1
BADCMD          EQU     2

FLAGVAL         EQU     $A9C5                   ;

		ORG	START

ENTRY:		MOVEA.L #STACK, SP
                MOVE.L	VECTORS, D0
                ST      (M68010)                ; Assume a 68010
                MOVE.L  #FLAGVAL, CURRENT
		DC.L    $4E7B0801               ; MOVEC	D0, VBR
                BRA     DOINIT
M68000          MOVEA.L #STACK, SP              ; Clear exception stack frame
                SF      (68010)                 ; Not a 68010
DOINIT          CLR.L   (CURRENT)
                BSR.W   DATAINIT
                MOVE.L	#STACK, USERSP
                BSR.W	INITDUART
                BSR.W   CRLF
		LEA	(HELLO).L, A0           ; Print startup message
		BSR.W	OUTSLN

CMDLOOP         MOVE.B  (ERROR), D0             ; Check for error in previous command
                EXT.W   D0
                BEQ     .GETCMD
                SUBQ    #1, D0                  ; Get error message
                ASL     #4, D0
                LEA.L   (ERRORTAB), A0
                ADDA.W  D0, A0
                BSR     OUTSLN                  ; Print it
                CLR.B   (ERROR)                 ; Clear error condition
.GETCMD         LEA.L   (PROMPT), A0
                BSR     OUTS
                BSR.W   GETLINE
                MOVE    (A0), D0                ; Get two character command into D0
                CMP.B   #'0', D0                ; Look for A/D register commands and breakpoints
                BLO     .LOOKUP
                CMP.B   #'7', D0
                BHI     .LOOKUP
                AND     #~$2000, D0             ; Uppercase register letter
                BRA     ADREGCMD
.LOOKUP         AND     #~$2020, D0             ; Uppercase both characters
                LEA.L   (CMDTAB), A2
.NEXT           CMP.W   (A2), D0
                BEQ     .DISPATCH
                TST     (A2)
                BEQ     EBADCMD
                ADDA    #6, A2
                BRA     .NEXT
.DISPATCH       MOVE.L  (2,A2), A2
                JMP     (A2)                    ; Dispatch command
EBADCMD         MOVE.B  #BADCMD, (ERROR)
                BRA     CMDLOOP

; Read/modify registers
;
SPREGCMD        LEA     USERSP, A1
                BRA     REGCMD

SRREGCMD        LEA     USERSR, A1
                BRA     REGCMD

PCREGCMD        LEA     USERPC, A1
                BRA     REGCMD

ADREGCMD        MOVE    D0, D1
                AND     #$00FF, D1              ; Get register digit
                SUB.B   #'0', D1                ; D1 = register number
                LSL     #2, D1                  ; D1 = register offset
                LSR     #8, D0
                CMP.B   #'A', D0
                BNE     .DREG
                LEA.L   USERA0, A1
                ADDA.W  D1, A1
                BRA     REGCMD
.DREG           CMP.B   #'D', D0
                BNE     .BKPTS
                LEA.L   USERD0, A1
                ADDA.W  D1, A1
                BRA     REGCMD
.BKPTS          CMP.B   #'B', D0                ; This code also sets breakpoint addresses
                BNE     EBADCMD
                LEA.L   BKPTS, A1
                ADDA.W  D1, A1

REGCMD          ADDA    #2, A0                  ; Move past command
                BSR     SKIPWS
                BEQ     .QRYREG                 ; End of line?
                BSR     PARSENUM
                TST.B   ERROR
                BNE     CMDLOOP
                CMP.L   #USERSR, A1
                BEQ     .UPDATESR
                MOVE.L  D1, (A1)
                BRA     CMDLOOP
.UPDATESR       MOVE    D1, (A1)                ; SR is a word register
                BRA     CMDLOOP

.QRYREG         MOVE.L  (A1), D0
                CMP.L   #USERSR, A1
                BEQ     .QRYSR
                BSR     PRHEX8
                BSR     CRLF
                BRA     CMDLOOP
.QRYSR          BSR     PRHEX4                  ; SR is a word register
                BSR     CRLF
                BRA     CMDLOOP

; Dump registers
;
DRCMD           BSR     DUMPREGS
                BRA     CMDLOOP

; Dump memory
;
DMCMD           ADDA    #2, A0                  ; Move past command
                BSR     READARGS                ; Dump memory in hex and ASCII
                TST.B   ERROR
                BNE     CMDLOOP                 ; Bail on an error
		BSR.W	DUMPMEM
		BSR.W	CRLF
		BRA     CMDLOOP

READARGS        BSR     SKIPWS                  ; Space after command
                BSR     PARSENUM
                TST.B   ERROR
                BNE     .ERR
                MOVE.L  D1, A1                  ; Initial address to A1
                BSR     SKIPWS
                CMP.B   #':', (A0)              ; x:y is the range from x to y
                BNE     .SIZE
                ADDQ    #1, A0                  ; Step over :
                BSR     SKIPWS
                BSR     PARSENUM
                TST.B   ERROR
                BNE     .ERR
                SUB.L   A1, D1                  ; Subtract to get byte length in D1
                BMI     .ERR
                RTS
.SIZE           BSR     PARSENUM                ; x y is from x for y bytes
                TST.B   ERROR
                BNE     .ERR
                RTS                             ; Byte length in D1
.ERR            MOVE.B  #BADNUM, ERROR
                RTS

; Breakpoint list
;
BPLSTCMD        LEA     (BKPTS), A2
                MOVEQ   #-1, D2
.NEXT           ADDQ.L  #1, D2
                CMP     #8, D2
                BHS     CMDLOOP
                MOVE.L  (A2)+, A4               ; Get breakpoint address
                CMP     #$400, A4
                BLO     .NEXT
                MOVE.B  #'B', D0                ; Print breakpoint name
                BSR     OUTCH
                MOVE.B  #'0', D0
                ADD.B   D2, D0
                BSR     OUTCH
                MOVE    #2, D0
                BSR     SPACES
                BSR     DISASM
                BSR     OUTSLN
                BRA     .NEXT


* boot CP/M 68K from compact flash
* The program is stored starting from Logical Address 1
* copy program into $15000 to $20000 and then jump into $15000
CFDATA          equ     $FFE000                 ; CF data register
CFERR           equ     $FFE002                 ; CF error reg
CFSECTCNT       equ     $FFE005                 ; CF sector count reg
CF07            equ     $FFE007                 ; CF LA0-7
CF815           equ     $FFE009                 ; CF LA8-15
CF1623          equ     $FFE00B                 ; CF LA16-23
CF2427          equ     $FFE00D                 ; CF LA24-27
CFSTAT          equ     $FFE00F                 ; CF status/command reg

BOOTCPMCMD      LEA     BOOTCPM, A0             ; print boot CPM message
                BSR     OUTSLN
                LEA     $15000,A2               ; clear memory from $15000-$20000
                MOVE.W  #$B000/4-1, D6          ; ($20000-$15000)/4-1
CLRMEMBO	MOVE.L	#0,(A2)+                ; clear memory
		DBRA	D6,CLRMEMBO
		
		CLR.L	D5                      ; d5 is checksum of CP/M-68K code
		MOVE.L	#$40000001, LA2427      ; select logical addressing mode, start from LA 1
		MOVE.B	LA2427, CF2427          ; write logical address
		MOVE.B	LA1623, CF1623
		MOVE.B	LA815, CF815
		MOVE.B	LA07, CF07              ; least significant address bits
		LEA	$15000, A2              ; CP/M 68K starts from $15000 to $20000
		MOVE.W	#$58-1, D6              ; total number of sectors is 0x58
NEXTSECT	BSR	READCF
		ADD.L	#1, LA2427              ; next logical address
		MOVE.B	LA2427, CF2427          ; write logical address
		MOVE.B	LA1623, CF1623
		MOVE.B	LA815, CF815
		MOVE.B	LA07, CF07              ; least significant address bits
		DBRA	D6, NEXTSECT
		
ENDREADCF	LEA	$15000, A2              ; point to first line of CPM
		CMP.L	#$4EF90001, (A2)+       ; are the first two long words correct?
		BNE	BADCPM
		CMP.L	#$50504EF9, (A2)
		BNE	BADCPM
		LEA	CRCCPM, A0              ; print checksum accumulated in d5
		BSR	OUTS                    ; finish sending message out
		MOVE.L	D5,D0                   ; print content of d5
		BSR	PRHEX8
		BSR	CRLF
		LEA	RUNCPM, A0              ; print execute CP/M message
		BSR	OUTSLN                  ; finish sending message out before start CPM
		MOVEQ   #0, D0
		DC.L    $4E7B0801               ; MOVEC	D0, VBR
		JMP	$15000                  ; start CP/M will not return
		
BADCPM	        LEA	NOCPM, A0               ; print CP/M code does not exist
		BSR	OUTSLN
DO_BO9	        BRA	CMDLOOP

; read a sector of CF data, accumulate checksum in d5
READCF:	        MOVE.L	D7,-(SP)                ; save d7
		MOVEQ	#0, D7                  ; clear d7
		MOVE.B	#1, CFSECTCNT           ; read one sector count
		MOVE.B	#$20, CFSTAT            ; read sector command
CHKDRQ          BTST.B	#3, CFSTAT              ; check data request bit set before reading
		BEQ	CHKDRQ
		MOVE.W	#$FF ,D2                ; read 512 bytes
READCF1		MOVE.W	CFDATA, D7              ; get data and put in destination
		MOVE.W	D7, (A2)+
		ADD.L	D7, D5                  ; accumulate checksum
		DBRA	D2, READCF1
		MOVE.L	(SP)+, D7               ; restore d7
		RTS

; Disassemble one instruction at (A4)
; Return pointer to disassembly in (A0)
; A4 is updated to point at the next instruction
; All other registers preserved
DISASM          MOVEM.L D0-D7/A1-A3/A5-A6, -(SP)
		MOVE.L  (A4), D0                ; Disassemble instruction at (A4)
		MOVE.L  4(A4), D1
		MOVE.L  8(A4), D2
		LEA     INBUF, A5
		BSR     DCODE68K
		MOVEA.L A5, A0                  ; Put zero terminated result in (A0)
		CLR.B   1(A6)
		MOVEM.L (SP)+, D0-D7/A1-A3/A5-A6
                RTS

***************************************************************************
* TEST CODE
***************************************************************************
		MOVE    #20-1, D4               ; Disassemble 20 instructions
		LEA.L   ENTRY, A4               ; ...from here
.MORE		MOVE.L  (A4), D0
		MOVE.L  4(A4), D1
		MOVE.L  8(A4), D2
		LEA     INBUF, A5
		MOVE.W  D4, -(SP)
		BSR     DCODE68K
		MOVEA.L A5, A0
		MOVE.B  #0, 1(A6)
		BSR     OUTSLN
		MOVE.W  (SP)+, D4
		DBRA    D4, .MORE

		LEA.L   OUTBUF, A3
		MOVEA.L #$008000, A4
		LEA.L   ASSEM, A5
		LEA.L   ASSEMEND, A6
		BSR     PRREGS
		BSR     CODE68K
		BSR     PRREGS
		LEA.L   OUTBUF, A0               ; Dump memory in hex and ASCII
		MOVE.L	#$60, D1
		BSR.W	DUMPMEM
		BSR.W	CRLF

************************************************************************
*                  A3 = STORE POINTER
*                  A4 = PROGRAM COUNTER
*                  A5 = POINTER TO DATA TO ASSEMBLE
*                  A6 = POINTER TO END OF SOURCE DATA
*         BSR       CODE68K             ASSEMBLE
*                  A3 = POINTER TO LINE ASSEMBLED
*                  A4 = PROGRAM COUNTER
*                  A6 = POINTER END OF LINE ASSEMBLED
*                  D0-D2 = DATA ASSEMBLED
*                  D6 = NUMBER OF BYTES ASSEMBLED
*                  D7 = ERROR FLAG & POSITION OF ERROR

*         MOVE.L    A3,A5
*         ADD.L     #78,A3              A3 = MAX LINE
*MMDI26   CMP.L     A6,A3
*         BCS.S     MMDI27
*         MOVE.B    #' ',(A6)+          SPACE FILL LINE
*         BRA       MMDI26
*MMDI27   BSR       OUT1CR              PRINT LINE JUST ENTERED
*
*         TST.B     D7
*         BNE.S     MMDI30              ERROR; DON'T STORE DATA
*
*         LEA       SYSTACK+4,A2        A2 = TEMP AREA
*         MOVEM.L   D0/D1/D2,-(A2)      STORE DATA
*         MOVE.L    D6,D1               D1 = NUMBER OF BYTES TO STORE
*         SUB.L     #1,D1
*         MOVE.L    A4,A1               A1 = DATA STORE POINTER
*MMDI29   MOVE.B    (A2)+,D0
*         MOVE.B    D0,(A1)
*         MOVE.B    (A1)+,D2            INSURE DATA STORED
*         CMP.B     D0,D2
*         BNE       MM90
*         DBRA      D1,MMDI29
*         BRA       MMDI22
*************************************************************************


.LOOP		BSR.W	GETLINE                 ; Read user input to (A0)
                MOVE.L  A0, -(SP)
                BSR.W   OUTSLN                  ; Print what the user typed
                LEA.L   INBUF, A0               ; Dump memory in hex and ASCII
		MOVE.L	#$20, D1
		BSR.W	DUMPMEM
                MOVEA.L (SP)+, A0               ; Point back at the input
                BSR     PRREGS                  ; Show the registers
		BSR     PARSENUM                ; Parse the input
		BSR     PRREGS                  ; Show the registers again
		MOVE.L  D1, D0                  ; Print the parsed value in D1
		BSR.W	PRHEX8
		MOVE    #2, D0                  ; ...a couple of spaces...
		BSR     SPACES
                MOVE.B  ERROR, D0               ; ...and the error flag
                BSR     PRHEX2
                BSR     CRLF
                MOVE.B  #0, ERROR               ; Clear any error
		BRA     .LOOP






		BSR.W	OUTSLN                  ; Print it back
		MOVE.W	D1, D0                  ; Print number of characters typed in hex
		BSR.W	PRHEX4
		BSR.W	CRLF
		BSR.W	CRLF
		BSR.W	DUMPREGS                ; Dump the user registers
		MOVEA.L #$500, A0               ; Dump memory in hex and ASCII
		MOVE.L	#$100, D1
		BSR.W	DUMPMEM
		BSR.W	CRLF
		MOVE.W	#$A5C7, D0              ; Dump binary
		BSR.W	PRBIN
		BSR     CRLF
		TRAP	#11
		DC.W	0

ASSEM           DC.B    '    MULU    D2,D3'
ASSEMEND        DC.B    0
OUTBUF          DS.B    82




; FOR DEBUGGING THE MONITOR
PRREGS          MOVEM.L D0-D7/A0-A7, USERD0	; Save Registers
                MOVE    SR, USERSR
                BSR     DUMPREGS
                MOVEM.L USERD0, D0-D7/A0-A6
                RTS


; Initialise data area
DATAINIT	LEA	(USERD0).L, A0
		MOVE.W	#(DATAEND-USERD0)/4, D0
.LOOP		MOVE.L	#0, (A0)+
		DBRA	D0, .LOOP
		MOVE.W  #7, D0
		LEA     (BKPTINS+8*2), A0
		MOVE    #BKPT0+7, D1
.NEXT           MOVE.W  D1, -(A0)
                SUBQ    #1, D1
                DBRA    D0, .NEXT
		RTS

INITDUART	MOVEA.L #DUART, A6		; A6 points at DUART base
		MOVE.B	#$00, IMR(A6)		; Disable all interrupts
		MOVE.B	#$70, ACR(A6)		; BRG Select = set 1
		MOVE.B	#$03, SOPB(A6)		; Write $03 to Set Output Port Bits Command (Set OP2-OP7 high)
		MOVEQ	#$10, D0
		MOVE.B	D0, CRA(A6)		; Write $10 to CRA Reset MR pointer to MRA1
		MOVE.B	D0, CRB(A6)		; Write $10 to CRB Reset MR pointer to MRB1
		MOVEQ	#$13, D0
		MOVE.B	D0, MRA(A6)		; Write $93 to MRA1 - Error mode = BLOCK,  8 bits/char
		MOVE.B	D0, MRB(A6)		; Write $93 to MRB1 - Error mode = BLOCK,  8 bits/char
		MOVEQ	#$17, D0
		MOVE.B	D0, MRA(A6)		; Write $17 to MRA2 - CTS Enable Tx,  1 stop bit
		MOVE.B	D0, MRB(A6)		; Write $17 to MRB2 - CTS Enable Tx,  1 stop bit
		MOVEQ	#$05, D0
		MOVE.B	D0, CRA(A6)		; Write $05 to CRA - Enable Tx,  Enable Rx
		MOVE.B	D0, CRB(A6)		; Write $05 to CRB - Enable Tx,  Enable Rx
.DETECTBAUD	MOVEQ	#$CC, D1		; 38.4k Baud
.TESTBAUD	MOVE.B	D1, CSRA(A6)		; Write Baud rate to CSRA
		MOVE.B	D1, CSRB(A6)		; Write Baud rate to CSRB
		RTS


; Get a line into the line buffer (user callable)
; Buffer pointer in A0, Buffer size in D2,
; Returns line length in D1, other registers are preserved
; Buffer is null terminated
GETLINEUSR	MOVE.L D0, -(SP)
		BSR.S  GETLINEAUX
		MOVE.L (SP)+, D0
		RTS

; Get a line into the line buffer INBUF
; Returns line length in D1
; Buffer is null terminated
GETLINE		LEA	INBUF, A0
		MOVEM.L D0/D2, -(SP)
		MOVE.W	#INBUFSZ, D2
		BSR.S	GETLINEAUX
		MOVEM.L (SP)+, D0/D2
		RTS

; Common core for system and user line input
GETLINEAUX	MOVEQ	#0, D1
.NEXTCH		BSR.S	GETCH
		CMPI.B	#CR, D0			  ; Terminate on CR
		BEQ.S	.ENDL
		CMPI.B	#LF, D0			  ; Ignore LF
		BEQ.S	.NEXTCH
		CMPI.B	#DELETE, D0		  ; Delete?
		BEQ.S	.NEXTCH			  ; Ignore
		CMPI.B	#BKSP, D0		  ; Backspace?
		BNE.S	.SKIPCTRL		  ; If not then check for other control characters
		TST.W	D1			  ; Backspace at start of line is ignored
		BEQ.S	.NEXTCH
		SUBI.W	#1, D1			  ; Drop a character in the buffer
		BSR.S	OUTCH			  ; Echo Backspace
		MOVE.B	#SPACE, D0		  ; Then Space
		BSR.S	OUTCH
		MOVE.B	#BKSP, D0		  ; Then Backspace
		BSR.S	OUTCH
		BRA.S	.NEXTCH
.SKIPCTRL	CMPI.B	#SPACE, D0		  ; Ignore other control characters
		BLT.S	.NEXTCH
		CMP.W	D2, D1			  ; Buffer full?
		BGE.S	.NEXTCH			  ; Yup! Dump the character
		MOVE.B	D0, (A0, D1.W)		  ; Store character in buffer
		ADDQ.W	#1, D1			  ; Bump the buffer offset
		BSR.S	OUTCH			  ; Echo the character
		BRA.S	.NEXTCH			  ; Back for more
.ENDL		MOVE.B	#0, (A0, D1.W)		  ; Add a terminating zero
                BSR.W   CRLF                      ; New line on console
		RTS				  ; D1 contains the number of characters in the buffer


; Get the next input character in DO
GETCH		BTST	#$00, DUART+SRA		  ; Test SRA bit 0 - RxRdy
		BEQ.S	GETCH			  ; Loop until ready
		MOVE.B	DUART+TBA, D0		  ; Get the input character
		ANDI.B	#$7F, D0		  ; Clear high bit
		RTS

; Send the character in D0
OUTCH		BTST	#$02, DUART+SRA		  ; Test SRA bit 2 - TxRdy
		BEQ.S	OUTCH			  ; Loop until ready
		MOVE.B	D0, DUART+TBA		  ; Send character
		RTS

; Send the null terminated string at A0 leaving A0 pointing at the next byte after the null
OUTS		MOVE.L	D0, -(SP)		  ; Save D0
		BRA.S	.SKIP
.PCH		BSR.W	OUTCH
.SKIP		MOVE.B	(A0)+, D0
		BNE.S	.PCH
		MOVE.L	(SP)+, D0		  ; Restore D0
		RTS

OUTSLN          BSR     OUTS
                BRA     CRLF

; Send the null terminated string at A0
; Print, at most, D1 characters leave A0 pointing after the last character output
; NOTE: A0 will never be left pointing at a terminating NULL
; D1 will remain decremented by the number of characters output + 1, not including the NULL
OUTSSAFE	MOVE.L	D0, -(SP)		  ; Save D0
		BRA.S	.SKIP
.PCH		BSR.W	OUTCH
.SKIP		MOVE.B	(A0)+, D0
		DBNE	D1, .PCH
		CMPI	#0, (A0)
		BRA	.NOTNULL		  ; Skip over NULL if we just missed it
		ADDA	#1, A0
.NOTNULL	MOVE.L	(SP)+, D0		  ; Restore D0
		RTS

; Output a CR LF to start a new line
CRLF		MOVE.L	D0, -(SP)
		MOVE.B	#CR, D0
		BSR.W	OUTCH
		MOVE.B	#LF, D0
		BSR.W	OUTCH
		MOVE.L	(SP)+, D0
		RTS



; Print a single hex digit from the 4 LSBs of D0 - Destroys D0
PRHEXDIGIT	ANDI.B	#$F, D0			  ; Mask digit
		CMPI.B	#9, D0			  ; Convert
		BLE.S	.SKIP
		ADDI.B	#7, D0
.SKIP		ADDI.B	#'0', D0
		BSR.W	OUTCH			  ; Print hex digit
		RTS


; Print a hex byte in D0.B - All registers preserved
PRHEX2		MOVE.L	D0, -(SP)
		LSR.B	#4, D0
		BSR.S	PRHEXDIGIT
		MOVE.L	(SP), D0
		BSR.S	PRHEXDIGIT
		MOVE.L	(SP)+, D0
		RTS

; Print a hex word in D0.W - All registers preserved
PRHEX4		MOVE.L	D0, -(SP)
		LSR.W	#8, D0
		BSR.S	PRHEX2
		MOVE.L	(SP), D0
		BSR.S	PRHEX2
		MOVE.L	(SP)+, D0
		RTS

; Print a hex long word in D0.L - All registers preserved
PRHEX8		SWAP	D0
		BSR.S	PRHEX4
		SWAP	D0
		BSR.S	PRHEX4
		RTS

; Print D0.W in binary
PRBIN		MOVEM.L D0-D2, -(SP)
		MOVE.W	D0, D2
		MOVE.W	#$0F, D1		  ; 16 bits
.LOOP		MOVE.B	#$18, D0		  ; 2 * $18 is an ASCII '0'
		LSL.W	#1, D2			  ; Add an extend bit and it becomes a '1'
		ADDX.B	D0, D0
		BSR.W	OUTCH
		DBRA	D1, .LOOP
		MOVEM.L (SP)+, D0-D2
		RTS


; Print D0 spaces
SPACES		MOVE.L  D1, -(SP)
                MOVE.W  D0, D1
		MOVEQ   #SPACE, D0
		BRA.S   .NEXT
.LOOP		BSR.W	OUTCH
.NEXT		DBRA	D1, .LOOP
		MOVE.L  (SP)+, D1
		RTS

; Dump the User mode registers
DUMPREGS	MOVEM.L D0-D1/A0, -(SP)
		MOVEQ	#0, D1			 ; Register index
		LEA	USERD0, A0
.NEXT		BSR.S	DUMPREG			 ; Dump one address or data register
		ADDI	#1, D1
		MOVE.B	D1, D0
		ANDI.B	#3, D0
		BNE.S	.NEXT
		BSR.W	RHS			  ; Print the SR and PC on the RHS
		BSR.W	CRLF
		CMPI.B	#$10, D1		  ; Do all 16
		BLT.S	.NEXT
		BSR.W	CRLF
		LEA.L	PCLEGEND, A0		  ; Print PC =
		BSR.W	OUTS
		MOVE.L	(USERPC), A4              ; Print PC and disassembly
		MOVE.L  (A4), D0
		MOVE.L  4(A4), D1
		MOVE.L  8(A4), D2
		LEA     INBUF, A5
		BSR     DCODE68K
		MOVEA.L A5, A0
		MOVE.B  #0, 1(A6)
		BSR     OUTSLN
		MOVEM.L (SP)+, D0-D1/A0
		RTS

;D1 is an index into the User Registers
DUMPREG		MOVEQ	#2, D0
		BSR.S	SPACES
		MOVE.B	#'D', D0
		CMPI.B	#8, D1
		BLT.S	.DREG
		MOVE.B	#'A', D0
.DREG		BSR.W	OUTCH
		MOVE.B	D1, D0
		ANDI.B	#7, D0
		BSR.W	PRHEXDIGIT
		MOVE.B	#' ', D0
		BSR.W	OUTCH
		MOVE.B	#'=', D0
		BSR.W	OUTCH
		MOVE.B	#' ', D0
		BSR.W	OUTCH
		MOVE.W	D1, D0
		LSL.W	#2, D0
		MOVE.L	(A0, D0.W), D0
		BSR.W	PRHEX8
		RTS

; Print the User SR and PC on the right
; on lines 1, 2 and 4
RHS		MOVE.B	D1, D0
		SUBI.B	#4, D0
		BNE.S	.LINE2
		MOVE.L	 A0, D0
		LEA.L	SRBITS, A0		   ; Print the bit names
		BSR.W	OUTS
		MOVEA.L D0, A0
		RTS
.LINE2		SUBI.B	#4, D0
		BNE.S	.DONE
		MOVE.L	A0, D0
		LEA.L	SRLEGEND, A0		    ; Print SR =
		BSR.W	OUTS
		MOVEA.L D0, A0
		MOVE.W	(USERSR), D0
		BRA.W	PRBIN			    ; Print SR in binary
.DONE           RTS

SRBITS		DC.B	'	     T S  III   XNZVC', 0
SRLEGEND	DC.B	'    SR = ', 0
PCLEGEND	DC.B	'  PC = ', 0


; Dump memory from A1 for D1 bytes
DUMPMEM		MOVEM.L D0-D3, -(SP)
                SUBQ    #1, D1
		MOVEQ	#0, D3
		MOVE.L	A1, D0
		ANDI	#$FFFFFFFE, D0		  ; Round to an even address
		MOVEA.L D0, A1
.LINE		BSR.W	PRHEX8			  ; Print the address
		MOVEQ	#4, D0
		BSR.W	SPACES
		MOVEQ	#7, D2			  ; Print 8 words
.LOOP		MOVE.W	(A1)+, D0
		BSR.W	PRHEX4
		MOVE.B	#' ', D0
		BSR.W	OUTCH
		DBRA	D2, .LOOP
		SUB.L	#$10, A1		  ; Reset the memory pointer
		MOVEQ	#$F, D2
.LOOP2		MOVE.B	(A1)+, D0		  ; Now print 16 ASCII characters
		BSR.S	PASCII
		DBRA	D2, .LOOP2
		BSR.W	CRLF
		ADDI.B	#1, D3
		ANDI.B	#7, D3
		BNE.S	.NOBRK
		BSR.W	CRLF
.NOBRK		MOVE.L	A1, D0
		SUBI.L	#$10, D1
		BCC.S	.LINE
		MOVEM.L (SP)+, D0-D3
		RTS

; Print a printable ASCII character, otherwise print a dot
PASCII		CMPI.B	#DELETE, D0
		BGE.S	.DOT
		CMPI.B	#SPACE, D0
		BLT.S	.DOT
		BRA.W	OUTCH
.DOT		MOVE.B	#'.', D0
		BRA.W	OUTCH

; Parse the numerical value at A0 until the next space or null
;	&10		= decimal 10
;	$FF		= hex FF
;	F06A		= hex F06A (default)
; Result in D1
; A0 points at next unparsed character
;
; Numbers can only be terminated by space, (, ], : and end of line

PARSENUM        MOVEM.L D0/D2-D3, -(SP)
                SF      D4                      ; Assume hex
                CMP.B   #'&', (A0)              ; & indicates decimal
                BNE     .NOTDEC
                ST      D4                      ; D4 indicates decimal
                ADDQ    #1, A0
                BRA     .BEGIN
.NOTDEC         CMP.B   #'$', (A0)              ; $ (optional) indicates hex
                BNE     .BEGIN
                ADDQ    #1, A0
.BEGIN          SF      D3                      ; D3 indicates valid digit seen
                CLR.L   D1                      ; Clear accumulator
                CLR.L   D0
.NEXT           MOVE.B  (A0), D0                ; Parse next digit
                BSR     PARSEDIG
                BMI     .DONE                   ; Non digit character
                ADDQ    #1, A0
                TST.B   D4
                BEQ     .MULHEX
                CMP.B   #9, D0
                BGT     .ERR                    ; Not a decimal digit
                CMP.L   #$1FFFFFFF, D1          ; Ensure we cannot overflow unaware
                BGT     .ERR
                MOVE.L  D1, D2
                ASL.L   #1, D1                  ; Multiply accumulator by 10
                ASL.L   #3, D2
                ADD.L   D2, D1
                BCS     .ERR
                BRA     .ADDDIG
.MULHEX         CMP.L   #$0FFFFFFF, D1          ; Ensure we cannot overflow unaware
                BGT     .ERR
                ASL.L   #4, D1                  ; Multiply accumulator by 16
.ADDDIG         ADD.L   D0, D1
                BCS     .ERR
                ST      D3                      ; Valid digit seen
                BRA     .NEXT
.DONE           TST.B   D3
                BEQ     .ERR                    ; No valid digits seen
                CMP.B   #SPACE, (A0)            ; Ensure the next character is EOL or whitespace
                BLS     .OK
                CMP.B   #'(', (A0)              ; or open paren
                BEQ     .OK
                CMP.B   #']', (A0)              ; or close bracket
                BEQ     .OK
                CMP.B   #':', (A0)              ; or colon
                BEQ     .OK
.ERR            MOVE.B  #BADNUM, ERROR          ; Set error flag
.OK             MOVEM.L (SP)+, D0/D2-D3
                RTS


; Parse digit in D0 for numeric input
; All of [A-Za-z0-9] are parsed to a numeric digit value in D0
; Invalid digits return $FFFF and set the N flag in the CCR
PARSEDIG        ANDI    #$FF, D0                ; Zero out the high bits
                CMPI.B  #'0', D0                ; Must be at least '0'
                BMI.S   .NOT
                CMP     #'9', D0                ; If <= 9 then it's decimal
                BLE.S   .DEC
                ANDI.B	#~$20, D0               ; Convert to upper case
                SUB 	#'A', D0                ; 'A' -> 0
		BMI	.NOT                    ; Reject lower
		CMP 	#$5, D0                 ; Reject more than 5
		BGT	.NOT
		ADD.B   #10, D0                 ; Adjust hex values to 10-15
		RTS
.NOT            MOVE.W  #$FFFF, D0              ; Failed, return negative
                RTS
.DEC            SUB.B   #'0', D0                ; Adjust decimal digits to 0-9
.OK             RTS


; Skip whitespace in null terminated buffer at (A0)
; Leave A0 at next non-whitespace character
; Actually skips anything less than '!' for simplicity
; Set Z flag in CCR if A0 is pointing at terminating null on exit
SKIPWS          CMP.B   #$0, (A0)
                BEQ     .DONE                   ; Terminating null
                CMP.B   #SPACE, (A0)
                BHI     .DONE                   ; Not Whitespace
                ADDQ    #1, A0
                BRA     SKIPWS
.DONE           RTS


; TRAP #11
; Stack contains Trap word arguments PC and SR (6 bytes)
TRAP11  	MOVE.L	A5, -(A7)		; Push A5
		MOVE.L	D0, -(A7)		; Push D0
		MOVEQ	#0, D0
		MOVEA.L $A(A7), A5		; Get saved PC, which points at the word following the trap instruction
		MOVE.W	(A5), D0		; Get Trap word
		ADDQ.L	#2, $A(A7)		; Move return PC past the word
		LSL.W	#2, D0			; Multiply argument by 4
		CMPI.L	#T11VEND-T11VEC, D0	; Check if in range
		BGE.L	.BADARG			; Nope!
		LEA	T11VEC(PC), A5		; Get base of vector table
		ADDA.L	D0, A5			; Get vector address
		MOVEA.L (A5), A5		; Get vector
		MOVE.L	(A7)+, D0		; Restore D0
		JSR	(A5)			; Call subroutine at vector address
		MOVE	SR, -(A7)		; Push SR
		MOVE.B	1(A7), 7(A7)		; Copy flags to saved flags
		ADDQ.L	#2, A7			; Drop flags
		MOVE.L	(A7)+, A5		; Restore A5
		RTE				; Return to User mode
 ; Invalid Trap #11 command
.BADARG		MOVE.L (A7)+, D0		; Restore D0
		MOVE.L (A7)+, A5		; Restore A5
		MOVEM.L D0-D7/A0-A6, -(A7)	; Save all registers
; Report error
		LEA	.T11ERROR, A0
		BSR.W	OUTS
.T11ERROR	DC.B	'Trap #11 - vector out of range\r\n', 0

T11VEC	       *DC.L	REENTER
		DC.L	GETCH
		DC.L	OUTCH
		DC.L	GETLINEUSR
		DC.L	OUTS
		DC.L    OUTSLN
		DC.L    CRLF
		DC.L	PRHEX2
		DC.L	PRHEX4
		DC.L	PRHEX8
		DC.L	SPACES

T11VEND

BUSERR
ADDRERR
ILLEGAL         BTST.B  #5, 1(SP)               ; Test the supervisor flag
                BNE     .SUPER
                MOVEM.L D0-D7/A0-A7, (USERD0)   ; Save user mode registers
                MOVE    (SP)+, (USERSR)
                MOVE.L  (SP)+, (USERPC)
                MOVE    (USERPC), D0            ; Get faulted instruction
                BSR     SWAPBKPTS               ; Swap out the breakpoints
                AND     #~$7, D0                ; Test for BKPT instruction
                CMP     #BKPT0, D0              ; A breakpoint has been hit
                BEQ     .DOBKPT


                ; DO MORE STUFF HERE
.DOBKPT

; Illegal instruction trap in supervisor mode
.SUPER          CMP     #FLAGVAL, (CURRENT)     ; Is this the processor test?
                BEQ     M68000                  ; We detected an M68000
                LEA     (ILLMSG), A0
                BSR     OUTSLN
                LEA     (PCMSG), A0
                BSR     OUTS
                ADD     #2, SP
                MOVE.L  (SP)+, D0               ; Get faulted PC
                BSR     PRHEX8                  ; Display it
                BSR     CRLF
                BRA     CMDLOOP


SWAPBKPTS       MOVEQ   #7, D2
                LEA     BKPTS, A0
                LEA     BKPTINS, A1
.NEXT           CMP     #$400, (A0)
                BLO     .NOBKPT
                MOVE.L  (A0), A2                ; Get code location
                MOVE    (A2), D0                ; Swap BKPTINS value and code word
                MOVE    (A1), D1
                MOVE    D1, (A2)
                MOVE    D0, (A1)
.NOBKPT         ADDQ    #4, A0
                ADDQ    #2, A1
                DBRA    D2, .NEXT
                TST.B   BKPTSON                 ; Flip the indicator flag
                SEQ     BKPTSON
                RTS


ILLMSG         DC.B    'ILLEGAL INSTRUCTION EXCEPTION', 0
BKPTMSG        DC.B    'BREAKPOINT ', 0
PCMSG          DC.B    'PC = ', 0
                DS.W    0

UNKNOWN
TRACE

TRAP15          JMP     ENTRY



MAINLOOP
		BRA.W	GETLINE

HELLO           DC.B    '~~~~~~~~~~~~~~~~~~', CR, LF
		DC.B	'AJBMON for Tiny68k', CR, LF
		DC.B    '~~~~~~~~~~~~~~~~~~', 0

PROMPT          DC.B    '~> ', 0

BOOTCPM         DC.B    'Copying CP/M 68K from Compact Flash...', 0
CRCCPM          DC.B    'Checksum is ',0
NOCPM           DC.B    'No valid CP/M code, command cancelled', 0
RUNCPM          DC.B    'CP/M-68K V1.3 COPYRIGHT (C) 1982, 1984, 1985 Digital Research', 0

                DS.W    0                       ; Move to even address

CMDTAB          DC.B    'DR'                    ; Dump Registers
                DC.L    DRCMD

                DC.B    'DM'                    ; Dump Memory
                DC.L    DMCMD

                DC.B    'SR'                    ; Status Register
                DC.L    SRREGCMD

                DC.B    'SP'                    ; Stack Pointer
                DC.L    SPREGCMD

                DC.B    'PC'                    ; Program Counter
                DC.L    PCREGCMD

                DC.B    'BL'                    ; Breakpoint List
                DC.L    BPLSTCMD

                DC.B    'BO'                    ; Boot CP/M
                DC.L    BOOTCPMCMD

                DC.W    0

ERRORTAB        DC.B    'BAD NUMBER', 0, 0, 0, 0, 0, 0
                DC.B    'BAD COMMAND', 0, 0, 0, 0, 0
                DS.W    0

                INCLUDE 'DCODE68K.X68'

                INCLUDE 'CODE68K.X68'


		END	ENTRY		 ; last line of source




































*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~8~
