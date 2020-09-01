*-----------------------------------------------------------
* Title	     : Tiny68k monitor
* Written by : A J Le Couteur Bisson
* Date	     : 31 Aug 2020
* Description:
*-----------------------------------------------------------

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
VECTORS		EQU	$8000
DATA		EQU	VECTORS+$400
START		EQU	DATA+$400



*********************************
* Vectors
*********************************
		ORG	VECTORS
		
		DC.L	STACK			* stack at the top task space
		DC.L	START			* start address of Tiny68kbug
		DC.L	BUSERR			* BERR handler
		DC.L	ADDRERR			* address error handler
		DC.L	ILLEGAL			* illegal instruction used as breakpoint
		DCB.L	4,UNKNOWN
		DC.L	TRACE			* trace handling
		DCB.L	37,UNKNOWN
		DC.L	TRAP15			* trap 15 implementing EASy68K trap services	
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
	 	
BAUDRATE	DS.B	1
ERROR		DS.B	1
	    
INBUFSZ		EQU	80
INBUF		DS.B	INBUFSZ+2


BKSP		EQU	$08
TAB		EQU	$09
LF		EQU	$0A
CR		EQU	$0D
CTRLX		EQU	$18
ESC		EQU	$1B
SPACE		EQU	$20
DELETE		EQU	$7F

BADNUM          EQU     $1

		ORG	START
		
ENTRY:		MOVE.L	VECTORS, D0
*		DC.L    $4E7B0801   
                * MOVEC	D0, VBR
                MOVEA.L #STACK, SP
                MOVE.B  #0, ERROR
                BSR.W	INITDUART
                BSR.W   USERINIT
                BSR.W   CRLF
		LEA	(HELLO).L, A0           ; Print startup message
		BSR.W	OUTSLN
.LOOP		BSR.W	GETLINE                 ; Read user input
                MOVE.L  A0, -(SP)
                BSR.W   OUTSLN
                MOVEA.L (SP)+, A0
                BSR     PRREGS
		BSR     PARSENUM
		MOVE.L  D1, D0
		BSR.W	PRHEX8
		MOVE    #2, D0
		BSR     SPACES
                MOVE.B  ERROR, D0
                BSR     PRHEX2
                BSR     CRLF
                BSR     PRREGS
                MOVE.B  #0, ERROR
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
		
PRREGS          MOVEM.L D0-D7/A0-A7, USERD0	; Save Registers
                MOVE    SR, USERSR
                BSR     DUMPREGS
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
		
* Buad rate detection		
		BSR.W	GETCH			; Get character from Port A to D0
		BSR.W	GETCH			; Get character from Port A to D0
		CMPI.B	#CR, D0			; Check for <CR>
		BEQ.S	.BAUDOK			; Success
		SUBI.B	#$11, D1		; Change baud rate
		CMPI.B	#$FF, D1		; Check for end of loop
		BEQ.S	.DETECTBAUD		; Try again from the top
		BRA.S	.TESTBAUD		; Try next baud rate
.BAUDOK	ANDI.B	#$F0, BAUDRATE.L	 	; Store baud rate
		ANDI.B	#$0F, D1
		OR.B	D1, BAUDRATE.L
		NOP
		NOP
		RTS

; Initialise User registers to zero except for the User Stack Pointer
; which is initialised to INITUSERSP
USERINIT	LEA	(USERD0).L, A0
		MOVE.W	#(USERSR-USERD0)/4, D0
.LOOP		MOVE.L	#0, (A0)+
		DBRA	D0, .LOOP
		MOVE.L	#STACK, USERSP
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
		CMPI	#0, (a0)
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
SPACES		MOVEM.L D0-D1, -(SP)
                MOVE.W  D0, D1
		MOVEQ   #SPACE, D0      
		BRA.S   .NEXT
.LOOP		BSR.W	OUTCH
.NEXT		DBRA	D1, .LOOP
		MOVEM.L (SP)+, D0-D1
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
		BNE.S	.LINE4
		MOVE.L	A0, D0	    
		LEA.L	SRLEGEND, A0		    ; Print SR =
		BSR.W	OUTS
		MOVEA.L D0, A0
		MOVE.W	USERSR, D0
		BRA.W	PRBIN			    ; Print SR in binary
.LINE4		SUBI.B	#8, D0
		BNE.S	.DONE
		MOVE.L	A0, D0	    
		LEA.L	PCLEGEND, A0		    ; Print PC = 
		BSR.W	OUTS
		MOVEA.L D0, A0
		MOVE.L	USERPC, D0
		BSR.W	PRHEX8			    ; Print PC in hex
.DONE		RTS		  
 
SRBITS		DC.B	'	     T S  III   XNZVC', 0
SRLEGEND	DC.B	'    SR = ', 0
PCLEGEND	DC.B	'    PC = ', 0		    
		

; Dump memory from A0 for D1 bytes			    
DUMPMEM		MOVEM.L D0-D3, -(SP)
		MOVEQ	#0, D3
		MOVE.L	A0, D0
		ANDI	#$FFFFFFFE, D0		  ; Round to an even address
		MOVEA.L D0, A0
.LINE		BSR.W	PRHEX8			  ; Print the address
		MOVEQ	#4, D0
		BSR.W	SPACES
		MOVEQ	#7, D2			  ; Print 8 words
.LOOP		MOVE.W	(A0)+, D0
		BSR.W	PRHEX4
		MOVE.B	#' ', D0
		BSR.W	OUTCH
		DBRA	D2, .LOOP
		LEA.L	-$10(A0), A0		  ; Reset the memory pointer
		MOVEQ	#$F, D2
.LOOP2		MOVE.B	(A0)+, D0		  ; Now print 16 ASCII characters
		BSR.S	PASCII
		DBRA	D2, .LOOP2
		BSR.W	CRLF
		ADDI.B	#1, D3
		ANDI.B	#7, D3
		BNE.S	.NOBRK
		BSR.W	CRLF
.NOBRK		MOVE.L	A0, D0
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
;	#10		= decimal 10
;	%1011		= binary 1011
;	F06A		= hex F06A (default)
; Result in D1
PARSENUM        MOVEM.L D0/D2-D3, -(SP)
                MOVE    #16, D2                 ; Assume hex
                CMP.B   #'#', (A0)              ; Check for decimal
                BNE     .NOTDEC
                MOVE    #10, D2
                ADDA    #1, A0
                BRA     .NOTBIN
.NOTDEC         CMP.B   #'%', (A0)              ; Check for binary
                BNE     .NOTBIN
                MOVE    #2, D2
                ADDA    #1, A0                
.NOTBIN         CLR.L   D1
                CLR.l   D0
.NEXT           MOVE.B  (A0)+, D0               ; Parse next digit
                BSR     PARSEDIG
                BMI     .DONE                   ; Non digit character
                CMP     D2, D0                  ; Check if the digit is valid in the base
                BGE     .ERR
                MOVE.L  D1, D3                  ; Multiply accumulator lo word by base
                MULU    D2, D3
                EXG.L   D1, D3                  ; Product back in accumulator
                SWAP    D3                      ; Get hi word
                MULU    D2, D3                  ; Multiply by base
                SWAP    D3                      ; Shift into hi word
                TST.W   D3                      ; Check for overflow
                BNE     .ERR                    ; Overflow if hi word was not zero
                ADD.L   D3, D1                  ; Add hi word of product
                BVS     .ERR  
		ADD.L   D0, D1                  ; Add new digit
		BVS     .ERR
		BRA     .NEXT                   ; Read the next digit
.DONE           CMP.B   #SPACE, (A0)            ; Ensure the next character is EOL or whitespace
                BHI     .OK
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
SKIPWS          CMP     #$0, (A0)
                BEQ     .DONE                   ; Terminating null
                CMP     #SPACE, (A0)
                BHI     .DONE                   ; Not Whitespace
                ADDA    #1, A0
                BRA     SKIPWS
.DONE           RTS                

      
; Enter supervisor mode
SMODE		MOVEM.L D0-D7/A0-A6, (USERD0)	  ; Save Registers	 
		MOVE	USP, A0			  ; Save User SP
		MOVE.L	A0, USERSP
		MOVE.W	(SP)+, D0		  ; Save User SR
		MOVE.W	D0, USERSR
		MOVE.L	(SP)+, D0		  ; Save User PC
		MOVE.L	D0, USERPC
		BRA.W	MAINLOOP

;Enter user mode
UMODE		MOVEA.L USERSP, A0		  ; Restore User SP
		MOVE	A0, USP
		MOVE.L	USERPC, D0		  ; Restore User PC to exception frame
		MOVE.L	D0, -(SP)
		MOVE.W	USERSR, D0		  ; Restore User SR to exception frame
		MOVE.W	D0, -(SP)
		MOVEM.L USERD0, D0-D7/A0-A6	  ; Restore other registers
		RTE				  ; Return to User mode
		
; TRAP #11
; Stack contains Trap word arguments PC and SR (6 bytes)
TRAP11HDLR	MOVE.L	A5, -(A7)		; Push A5
		MOVE.L	D0, -(A7)		; Push D0
		MOVEQ	#0, D0			
		MOVEA.L $A(A7), A5		; Get saved PC, which points at the word following the trap instruction
		MOVE.W	(A5), D0			; Get Trap word
		ADDQ.L	#2, $A(A7)		; Move return PC past the word
		LSL.W	#2, D0			; Multiply argument by 4
		CMPI.L	#T11VEND-T11VEC, D0	; Check if in range
		BGE.L	.BADARG			; Nope!
		LEA	T11VEC(PC), A5		; Get base of vector table
		ADDA.L	D0, A5			; Get vector address
		MOVEA.L (A5), A5			; Get vector
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
		LEA	T11ERROR, A0
		BSR.W	OUTS
T11ERROR	DC.B	'Trap #11 - vector out of range\r\n', 0

T11VEC	       *DC.L	REENTER
		DC.L	GETCH
		DC.L	OUTCH
		DC.L	OUTS
		DC.L	PRHEX2
		DC.L	PRHEX4
		DC.L	PRHEX8
		DC.L	SPACES
		DC.L	GETLINEUSR
T11VEND		

BUSERR
ADDRERR
ILLEGAL
UNKNOWN
TRACE
TRAP15          JMP     ENTRY
       
		
		
MAINLOOP
		BRA.W	GETLINE
				
HELLO		DC.B	'AJBMON for Tiny68k', 0	

		
		END	ENTRY		 ; last line of source
















*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~8~
