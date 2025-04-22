*-----------------------------------------------------------
* Title      : Tiny68k monitor
* Written by : A J Le Couteur Bisson
* Date       : 31 Aug 2020
* Description:
*-----------------------------------------------------------
                OPT     MEX


*********************************
* 68681 Duart Register Addresses
*********************************
DUART           EQU     $FFF000                 ; Base Addr of DUART
MRA             EQU     $1                      ; Mode Register A               (R/W)
SRA             EQU     $3                      ; Status Register A             (R)
CSRA            EQU     $3                      ; Clock Select Register A       (W)
CRA             EQU     $5                      ; Commands Register A           (W)
RBA             EQU     $7                      ; Receiver Buffer A             (R)
TBA             EQU     $7                      ; Transmitter Buffer A          (W)
ACR             EQU     $9                      ; Aux. Control Register         (R/W)
ISR             EQU     $B                      ; Interrupt Status Register     (R)
IMR             EQU     $B                      ; Interrupt Mask Register       (W)
MRB             EQU     $11                     ; Mode Register B               (R/W)
SRB             EQU     $13                     ; Status Register B             (R)
CSRB            EQU     $13                     ; Clock Select Register B       (W)
CRB             EQU     $15                     ; Commands Register B           (W)
RBB             EQU     $17                     ; Reciever Buffer B             (R)
TBB             EQU     $17                     ; Transmitter Buffer B          (W)
IVR             EQU     $19                     ; Interrupt Vector Register     (R/W)
SOPB            EQU     $1D                     ; Set Output Port Bits Register (W)
COPB            EQU     $1F                     ; Clr Output Port Bits Register (W)

DEV             EQU     0                       ; 1 = Dev mode, 0 = ROM mode

                IFEQ    DEV
* ROM config
VECTORS         EQU     $0
DATA            EQU     $400                    ; Monitor data area
START           EQU     DATA+$400
RAMEND          EQU     $FF7FF0
STACK           EQU     RAMEND - 2
USERSTACK       EQU     STACK-$400
PROG            EQU     $4000
                ENDC



                IFNE    DEV
* Development config
VECTORS         EQU     $8000
DATA            EQU     VECTORS+$400
START           EQU     DATA+$400
RAMEND          EQU     $FF7FF0
STACK           EQU     RAMEND-2
USERSTACK       EQU     STACK-$400
PROG            EQU     $10000
                ENDC


*********************************
* Vectors
*********************************
                ORG     VECTORS

                DC.L    STACK                   * Supervisor stack at the top of RAM
                DC.L    ENTRY                   * Start address of monitor
                DC.L    BUSERR                  * BERR handler
                DC.L    ADDRERR                 * Address error handler
                DC.L    ILLEGAL                 * Illegal instruction handler also implements breakpoints
                DC.L    UNKNOWN                 * Zero divide
                DC.L    UNKNOWN                 * CHK
                DC.L    UNKNOWN                 * TRAPV
                DC.L    UNKNOWN                 * Privilege violation
                DC.L    TRACE                   * Trace handling
                DC.L    UNKNOWN                 * Line A emulation
                DC.L    UNKNOWN                 * Line B emulation
                DC.L    UNKNOWN                 * Reserved
                DC.L    UNKNOWN                 * Reserved
                DC.L    UNKNOWN                 * Format error
                DC.L    UNKNOWN                 * Uninitialised interrupt vector
                DC.L    UNKNOWN                 * Reserved
                DC.L    UNKNOWN                 * Reserved
                DC.L    UNKNOWN                 * Reserved
                DC.L    UNKNOWN                 * Reserved
                DC.L    UNKNOWN                 * Reserved
                DC.L    UNKNOWN                 * Reserved
                DC.L    UNKNOWN                 * Reserved
                DC.L    UNKNOWN                 * Reserved
                DC.L    NMI                     * Spurious interrupt (NMI is spurious because VPA is not asserted)
                DC.L    NMI                     * Level 1 interrupt autovector
                DC.L    NMI                     * Level 2 interrupt autovector
                DC.L    NMI                     * Level 3 interrupt autovector
                DC.L    NMI                     * Level 4 interrupt autovector
                DC.L    NMI                     * Level 5 interrupt autovector
                DC.L    NMI                     * Level 6 interrupt autovector
                DC.L    NMI                     * Level 7 interrupt autovector (NMI)
                DC.L    TRAP0                   * Trap 0
                DC.L    UNKNOWN                 * Trap 1
                DC.L    UNKNOWN                 * Trap 2
                DC.L    UNKNOWN                 * Trap 3
                DC.L    UNKNOWN                 * Trap 4
                DC.L    UNKNOWN                 * Trap 5
                DC.L    UNKNOWN                 * Trap 6
                DC.L    UNKNOWN                 * Trap 7
                DC.L    UNKNOWN                 * Trap 8
                DC.L    UNKNOWN                 * Trap 9
                DC.L    UNKNOWN                 * Trap 10
                DC.L    UNKNOWN                 * Trap 11
                DC.L    UNKNOWN                 * Trap 12
                DC.L    UNKNOWN                 * Trap 13
                DC.L    UNKNOWN                 * Trap 14
                DC.L    UNKNOWN                 * Trap 15 implementing EASy68K trap services
                DCB.L   16,UNKNOWN              * Reserved
                DCB.L   192,UNKNOWN             * User interrupt vectors                

                ORG DATA

; User register storage
USERD0          DS.L    1
USERD1          DS.L    1
USERD2          DS.L    1
USERD3          DS.L    1
USERD4          DS.L    1
USERD5          DS.L    1
USERD6          DS.L    1
USERD7          DS.L    1

USERA0          DS.L    1
USERA1          DS.L    1
USERA2          DS.L    1
USERA3          DS.L    1
USERA4          DS.L    1
USERA5          DS.L    1
USERA6          DS.L    1
USERA7
USERSP          DS.L    1

USERPC          DS.L    1
USERSR          DS.W    1


BKPTS           DS.L    8                       ; Breakpoint addresses (0 if not set)
OVERPT          DS.L    1                       ; Step over breakpoint (uses ILLEGAL instruction)
BKPTINS         DS.W    8                       ; Swapped out instruction at breakpoint address
OVERINS         DS.W    1                       ; Step over target instruction
BKPTSON         DC.B    1                       ; Set if breakpoints are installed
SETPKPTS        DC.B    1                       ; Set if we need to install the breakpoints
TRACEMODE       DC.B    1                       ; Set when tracing (So we know we are tracing when stepping over)
OVERMODE        DC.B    1                       ; Set if step over point installed
ERROR           DS.B    1                       ; Error code for monitor commands

                DS.W    0
LA2427          DS.B    1                       * head
LA1623          DS.B    1                       * cylinder high
LA815           DS.B    1                       * cylinder low
LA07            DS.B    1                       * sector

                DS.W    0

INBUFSZ         EQU     80                      ; User input buffer
INBUF           DS.B    INBUFSZ+2

ASMBUFSZ        EQU     80
ASMBUF          DS.B    ASMBUFSZ+2
                
CONTINUE        DS.L    1                       ; Continue address for commands
CONTSIZE        DS.L    1

DATAEND         DS.W    0

M68010          DS.B    1                       ; Set if 68010 processor
                DS.W    0

BKPT0           EQU     $4848                   ; BKPT #0 instruction


BKSP            EQU     $08
TAB             EQU     $09
LF              EQU     $0A
CR              EQU     $0D
CTRLX           EQU     $18
ESC             EQU     $1B
SPACE           EQU     $20
DELETE          EQU     $7F

BADNUM          EQU     1
BADCMD          EQU     2
NOTWRT          EQU     3
SRECERR         EQU     4
CSUMERR         EQU     5


                ORG     START
; Fixed vectors for monitor routines
VGETLINE        BRA     GETLINE
VGETCH          BRA     GETCH
VOUTCH          BRA     OUTCH
VOUTS           BRA     OUTS
VOUTSLN         BRA     OUTSLN
VCRLF           BRA     CRLF
VOUTSSAFE       BRA     OUTSSAFE
VPRHEXDIGIT     BRA     PRHEXDIGIT
VPRHEX2         BRA     PRHEX2
VPRHEX4         BRA     PRHEX4
VPRHEX6         BRA     PRHEX6
VPRHEX8         BRA     PRHEX8
VPRBIN8         BRA     PRBIN8
VPRBIN16        BRA     PRBIN16
VPRDEC          BRA     PRDEC
VPRSDEC         BRA     PRSDEC
VSPACES         BRA     SPACES
VSKIPWS         BRA     SKIPWS
VPARSENUM       BRA     PARSENUM
                
                                                
ENTRY:          MOVEA.L #STACK, SP
                MOVE.L  #VECTORS, D0
                ST      M68010                  ; Assume a 68010
MOVECADR        DC.L    $4E7B0801               ; MOVEC D0, VBR
                BRA     DOINIT
M68000          MOVEA.L #STACK, SP              ; Clear exception stack frame
                SF      M68010                  ; Not a 68010
DOINIT          BSR.W   DATAINIT
                BSR.W   INITDUART
                BSR.W   CRLF
                LEA     (HELLO).L, A0           ; Print startup message
                BSR.W   OUTSLN
                LEA     P00, A0
                TST.B   M68010
                BEQ     .PRPROC
                LEA     P10, A0
.PRPROC         BSR     OUTSLN

CMDLOOP         MOVEA.L #STACK, SP              ; Reset the stack
                MOVE.B  ERROR, D0               ; Check for error in previous command
                EXT.W   D0
                BEQ     .GETCMD
                SUBQ    #1, D0                  ; Get error message
                ASL     #4, D0
                LEA.L   (ERRORTAB), A0
                ADDA.W  D0, A0
                BSR     OUTSLN                  ; Print it
                CLR.B   ERROR                   ; Clear error condition
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
EBADCMD         MOVE.B  #BADCMD, ERROR
                BRA     CMDLOOP
                
P00             DC.B    'M68000', 0
P10             DC.B    'M68010', 0
                DS.W    0

; Print help text                
HELPCMD         LEA     HELPTXT, A0
                BSR     OUTS
                BRA     CMDLOOP
                             
; Execute user code

GOCMD           ADDA    #2, A0                  ; Move past command
                BSR     SKIPWS                  ; Space after command
                BEQ     GO               
                BSR     PARSENUM
                TST.B   ERROR
                BNE     CMDLOOP
                MOVE.L  D1, USERPC              ; Update PC
GO              
                TST.B   M68010
                BEQ     .NOFMT
                MOVE    #$0024, -(SP)           ; Dummy format 0 trace frame
.NOFMT          MOVE.L  USERPC, -(SP)           ; Push user PC
                MOVE    USERSR, D0
                AND     #$07FF, D0              ; Clear supervisor and trace flags
                MOVE    D0, -(SP)               ; Push SR
                MOVE.L  USERSP, A0
                MOVE.L  A0, USP
                MOVEM.L USERD0, D0-D7/A0-A6     ; Restore registers
                RTE 
                
; Single step user code
;
STEPCMD         ADDA    #2, A0                  ; Move past command
                BSR     SKIPWS                  ; Space after command
                BEQ     RESTEP               
                BSR     PARSENUM
                TST.B   ERROR
                BNE     CMDLOOP
                MOVE.L  D1, USERPC              ; Update PC
RESTEP          TST.B   M68010
                BEQ     .NOFMT
                MOVE    #$0024, -(SP)           ; Dummy format 0 trace frame
.NOFMT          MOVE.L  USERPC, -(SP)           ; Push user PC
                MOVE    USERSR, D0
                AND     #$07FF, D0              ; Clear supervisor and trace flags
                OR      #$8000, D0              ; Set trace flag
                MOVE    D0, -(SP)               ; Push SP
                MOVE.L  USERSP, A0
                MOVE.L  A0, USP
                MOVEM.L USERD0, D0-D7/A0-A6     ; Restore registers
                RTE

; Trace exception comes here
; Press space or enter to step again
; Press 'G' or 'g' to GO from the current PC
; Press any other key to return to the command prompt
TRACERPT        BSR     GETCH
                CMP.B   #' ', D0
                BLS     RESTEP
                AND.B   #~$40, D0               ; Ignore case
                CMP.B   #'G', D0
                BEQ     GO
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
.QRYSR          SWAP    D0                      ; Move data into low word
                BSR     PRHEX4                  ; SR is a word register
                BSR     CRLF
                BRA     CMDLOOP

; Dump registers
;
DRCMD           BSR     DUMPREGSDIS
                BRA     CMDLOOP

; Dump memory
;
DMCMD           ADDA    #2, A0                  ; Move past command
                BSR     READARGS                ; Dump memory in hex and ASCII
                TST.B   ERROR
                BNE     CMDLOOP                 ; Bail on an error
                BSR.W   DUMPMEM
                BSR.W   CRLF
                BRA     CMDLOOP
                
DISASMCMD       ADDA    #2, A0                  ; Move past command
                BSR     READARGS                ; Dump memory in hex and ASCII
                TST.B   ERROR
                BNE     CMDLOOP                 ; Bail on an error
                MOVEA.L A1, A4
.NEXT           BSR     DISASM
                BSR     OUTSLN
                CMPA.L  D2, A4
                BLO     .NEXT
                BRA     CMDLOOP

; Modify memory
; Insert data at address argument
; Lines may be hex data with optional spaces after a complete byte
; or a single quote followed by ASCII text to end of line
; Spaces in hex data may imply byte, word or long data but alignment is not checked 
MMCMD           ADDA    #2, A0                  ; Move past command
                BSR     SKIPWS                  ; Space after command
                BNE     .PARSEADDR               
                MOVEA.L CONTINUE, A1
                BRA     .NEXTLN             
.PARSEADDR      BSR     PARSENUM
                TST.B   ERROR
                BNE     CMDLOOP
                MOVEA.L D1, A1                  ; Initial address
.NEXTLN         MOVE.L  A1, D0
                BSR     PRHEX8
                MOVE    #2, D0
                BSR     SPACES
                BSR     GETLINE
                BSR     SKIPWS
                BEQ     CMDLOOP                 ; End on empty line
                MOVE.B  (A0), D0
                CMP.B   #$22, D0                ; Test for ASCII input
                BEQ     .MASCII 
.NEXT           BSR     SKIPWS                  ; Whitespace allowed after each byte
                BEQ     .NEXTLN                 ; End of line
                MOVE.B  (A0)+, D0
                BSR     PARSEDIG
                BMI     .ERR
                LSL     #4, D0
                MOVE    D0, D1
                MOVE.B  (A0)+, D0
                BEQ.S   .ERR                    ; Missing 2nd digit
                BSR     PARSEDIG
                BMI.S   .ERR
                ADD.B   D1, D0                  ; Byte constructed
                MOVE.B  D0, (A1)
                CMP.B   (A1)+, D0
                BNE.S   .NWRT     
                BRA     .NEXT
.ERR            MOVE.B  #BADNUM, ERROR          ; Bad hex data
                BRA     CMDLOOP
.NWRT           MOVE.B  #NOTWRT, ERROR          ; Address not writable
                BRA     CMDLOOP

.MASCII         ADDQ    #1, A0                  ; Skip over quote
.NXTCH          MOVE.B  (A0)+, D0
                BEQ     .NEXTLN
                MOVE.B  D0, (A1)
                CMP.B   (A1)+, D0
                BNE.S   .NWRT 
                BRA.S   .NXTCH

; Fetch 'start:end' or 'start size' arguments for memory commands
; A0 = Start
; D1 = Size
; D2 = End
READARGS        BSR     SKIPWS                  ; Space after command
                BNE     .PARSEARGS               
                MOVEA.L CONTINUE, A1            ; Continue with previous end and size
                MOVE.L  CONTSIZE, D1
                BRA     .DONE 
.PARSEARGS      BSR     PARSENUM
                TST.B   ERROR
                BNE     CMDLOOP
                MOVE.L  D1, A1                  ; Initial address to A1
                BSR     SKIPWS
                BNE     .READNEXT
                MOVE.L  CONTSIZE, D1            ; Default the size only
                BRA     .DONE
.READNEXT       CMP.B   #':', (A0)              ; x:y is the range from x to y
                BNE     .SIZE
                ADDQ    #1, A0                  ; Step over :
                BSR     SKIPWS
                BSR     PARSENUM
                TST.B   ERROR
                BNE     .ERR
                SUB.L   A1, D1                  ; Subtract to get byte length in D1
                BMI     .ERR
                BRA     .DONE
.SIZE           BSR     PARSENUM                ; x y is from x for y bytes
                TST.B   ERROR
                BNE     CMDLOOP
.DONE           BCLR    #0, D0                  ; Ensure we are on word boundaries
                BCLR    #0, D1
                MOVE.L  A1, D2
                ADD.L   D1, D2                  ; Continue from here
                MOVE.L  D2, CONTINUE
                MOVE.L  D1, CONTSIZE
                RTS                             ; Byte length in D1
.ERR            MOVE.B  #BADNUM, ERROR

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
*         MOVE.B    (A1)+,D2            ENSURE DATA STORED
*         CMP.B     D0,D2
*         BNE       MM90
*         DBRA      D1,MMDI29
*         BRA       MMDI22
*************************************************************************

*ASSEMCMD        ADDA    #2, A0                  ; Move past command
*                BSR     SKIPWS                  ; Space after command
*                BNE     .PARSEADDR               
*                MOVEA.L CONTINUE, A4
*                BRA     .NEXT
*.PARSEADDR      BSR     PARSENUM
*                TST.B   ERROR
*                BNE     CMDLOOP
*                MOVEA.L D1, A4                  ; Initial address to A4
*.NEXT           MOVE.L  A4, D0
*                AND.L   #$FFFFFF, D0            ; Set assembly PC high byte to zero
*                MOVEA.L D0, A4
*                BSR     PRHEX6                  ; Prompt with address
*                MOVE    #2, D0
*                BSR     SPACES
*                BSR     GETLINE                 ; Read assembly input
*                MOVEA.L A0, A5                  ; Input to assemble
*                MOVEA.L A0, A6
*                ADDA    D1, A6                  ; End of input
*                LEA     ASMBUF, A3
*                
*                BSR     PRREGS
*                
*                MOVE.L  D1, -(SP)
*                MOVEA.L A5, A1
*                MOVE.L  #80, D1
*                BSR     DUMPMEM
*                MOVE.L  (SP)+, D1
*                
*                BSR     CODE68K                 ; Assemble
*                
*                BSR     PRREGS
*               
*                MOVE.L  D1, -(SP)
*                MOVEA.L A3, A1
*                MOVE.L  #80, D1
*                BSR     DUMPMEM
*                MOVE.L  (SP)+, D1
*                
*                MOVEA.L A3, A0
*                CLR.B   1(A6)                   ; Null terminate
*
*                BSR     OUTSLN
*                TST     D7
*                BEQ     .ASMOK
*                MOVE    D7, D0
*                SUBQ    #1, D0
*                BSR     SPACES
*                MOVE    #'^', D0
*                BSR     OUTCH
*                BSR     CRLF
*                BRA     .NEXT
*.ASMOK          MOVE.B  #0, 1(A6)               ; Null terminate
*                MOVEA.L A3, A0
*                BSR     OUTSLN
*                MOVE    D0, (A4)+
*                SUBQ    #2, D6
*                BEQ     .NEXT
*                MOVE    D1, (A4)+
*                SUBQ    #2, D6
*                BEQ     .NEXT
*                MOVE    D2, (A4)+
*                BRA     .NEXT

; Load S-Records
SRECCMD         BSR     GETLINE                 ; Get next line
                CMP.B   #10, D1
                BMI     SRERR                   ; Line too short
                CMP.B   #'S', (A0)+
                BNE     SRERR
                MOVE    D1, D2                  ; Save line length
                MOVE.B  (A0)+, D0               ; Get record type
                CMP.B   #'0', D0
                BEQ     SRECCMD                 ; Ignore header record
                CMP.B   #'1', D0                ; 16 bit data record
                BEQ     S1
                CMP.B   #'2', D0                ; 24 bit data record
                BEQ     S2
                CMP.B   #'5', D0                ; Ignore count record
                BEQ     SRECCMD 
                CMP.B   #'8', D0                ; Termination record
                BEQ     S8 
                CMP.B   #'9', D0                ; Termination record
                BEQ     S9
                BRA     SRERR                   ; Unrecognised cmd
                
S1              CLR.L   D4                      ; Clear checksum
                BSR     GETBYTE
                MOVE    D0, D3                  ; Save byte count
                ADDQ    #2, D0
                LSL     #1, D0
                CMP     D0, D2                  ; Check line length against count
                BNE     SRERR
                BSR     GETWORD
                MOVEA.L D0, A1                  ; A1 is target address
                SUBQ    #4, D3                  ; Get data byte count - 1
                BMI     SRERR
.LOOP           BSR     GETBYTE
                MOVE.B  D0, (A1)+
                DBRA    D3, .LOOP
                BSR     GETBYTE                 ; Get the checksum
                CMP.B   #$FF, D4
                BEQ     SRECCMD
                BRA     CSERR


S2              CLR.L   D4                      ; Clear checksum
                BSR     GETBYTE
                MOVE    D0, D3                  ; Save byte count
                ADDQ    #2, D0
                LSL     #1, D0
                CMP     D0, D2                  ; Check line length against count
                BNE     SRERR
                BSR     GET24
                MOVEA.L D0, A1                  ; A1 is target address
                SUBQ    #5, D3                  ; Get data byte count - 1
                BMI     SRERR
.LOOP           BSR     GETBYTE
                MOVE.B  D0, (A1)+
                ADD     D0, D4
                DBRA    D3, .LOOP
                BSR     GETBYTE                 ; Get the checksum
                CMP.B   #$FF, D4
                BEQ     SRECCMD
CSERR           MOVE.B  #CSUMERR, ERROR
                BRA     CMDLOOP
SRERR           MOVE.B  #SRECERR, ERROR
                BRA     CMDLOOP

S8              CLR.L   D4                      ; Clear checksum
                BSR     GETBYTE
                CMP.B   #4, D0
                BNE     SRERR
                BSR     GET24
                MOVE.L  D0, USERPC              ; Store execution address
                BSR     GETBYTE                 ; Get the checksum
                CMP.B   #$FF, D4
                BEQ     CMDLOOP                 ; Done
                BRA     CSERR
                
S9              CLR.L   D4                      ; Clear checksum
                BSR     GETBYTE
                CMP     #3, D0
                BNE     SRERR
                BSR     GETWORD
                MOVE.L  D0, USERPC              ; Store execution address
                BSR     GETBYTE                 ; Get the checksum
                CMP.B   #$FF, D4
                BEQ     CMDLOOP                 ; Done
                BRA     CSERR

GETLONG         BSR     GETWORD
                SWAP    D0
                MOVE.L  D0, D1
                BSR     GETWORD
                ADD.L   D1, D0
                RTS

GET24           BSR     GETWORD
                LSL.L   #8, D0
                MOVE.L  D0, D1
                BSR     GETBYTE
                ADD.L   D1, D0
                RTS

GETWORD         BSR     GETBYTE
                LSL     #8, D0
                MOVE    D0, D1
                BSR     GETBYTE
                ADD     D1, D0
                RTS

GETBYTE         MOVE.B  (A0)+, D0
                BSR     PARSEDIG
                BMI     .ERR
                LSL     #4, D0
                MOVE    D0, D5
                MOVE.B  (A0)+, D0
                BSR     PARSEDIG
                BMI     .ERR
                ADD.B   D5, D0
                ADD.B   D0, D4                    ; Accumulate checksum
                RTS
.ERR            MOVE.B  #BADNUM, ERROR
                BRA     CMDLOOP                   ; Ideally this should swallow input until it stops

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
CLRMEMBO        MOVE.L  #0,(A2)+                ; clear memory
                DBRA    D6,CLRMEMBO
                
                CLR.L   D5                      ; d5 is checksum of CP/M-68K code
                MOVE.L  #$40000001, LA2427      ; select logical addressing mode, start from LA 1
                MOVE.B  LA2427, CF2427          ; write logical address
                MOVE.B  LA1623, CF1623
                MOVE.B  LA815, CF815
                MOVE.B  LA07, CF07              ; least significant address bits
                LEA     $15000, A2              ; CP/M 68K starts from $15000 to $20000
                MOVE.W  #$58-1, D6              ; total number of sectors is 0x58
NEXTSECT        BSR     READCF
                ADD.L   #1, LA2427              ; next logical address
                MOVE.B  LA2427, CF2427          ; write logical address
                MOVE.B  LA1623, CF1623
                MOVE.B  LA815, CF815
                MOVE.B  LA07, CF07              ; least significant address bits
                DBRA    D6, NEXTSECT
                
ENDREADCF       LEA     $15000, A2              ; point to first line of CPM
                CMP.L   #$4EF90001, (A2)+       ; are the first two long words correct?
                BNE     BADCPM
                CMP.L   #$50504EF9, (A2)
                BNE     BADCPM
                LEA     CRCCPM, A0              ; print checksum accumulated in d5
                BSR     OUTS                    ; finish sending message out
                MOVE.L  D5,D0                   ; print content of d5
                BSR     PRHEX8
                BSR     CRLF
                LEA     RUNCPM, A0              ; print execute CP/M message
                BSR     OUTSLN                  ; finish sending message out before start CPM
                MOVEQ   #0, D0
                DC.L    $4E7B0801               ; MOVEC D0, VBR
                JMP     $15000                  ; start CP/M will not return
                
BADCPM          LEA     NOCPM, A0               ; print CP/M code does not exist
                BSR     OUTSLN
DO_BO9          BRA     CMDLOOP

; read a sector of CF data, accumulate checksum in d5
READCF:         MOVE.L  D7,-(SP)                ; save d7
                MOVEQ   #0, D7                  ; clear d7
                MOVE.B  #1, CFSECTCNT           ; read one sector count
                MOVE.B  #$20, CFSTAT            ; read sector command
CHKDRQ          BTST.B  #3, CFSTAT              ; check data request bit set before reading
                BEQ     CHKDRQ
                MOVE.W  #$FF ,D2                ; read 512 bytes
READCF1         MOVE.W  CFDATA, D7              ; get data and put in destination
                MOVE.W  D7, (A2)+
                ADD.L   D7, D5                  ; accumulate checksum
                DBRA    D2, READCF1
                MOVE.L  (SP)+, D7               ; restore d7
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

; FOR DEBUGGING THE MONITOR
PRREGS          MOVEM.L D0-D7/A0-A6, USERD0     ; Save Registers
                MOVE    SR, USERSR
                BSR     DUMPREGS
                MOVEM.L USERD0, D0-D7/A0-A6
                MOVE    USERSR, SR
                RTS


; Initialise data area
DATAINIT        LEA     (USERD0).L, A0
                MOVE.W  #(DATAEND-USERD0)/4-1, D0
.LOOP           MOVE.L  #0, (A0)+
                DBRA    D0, .LOOP
                MOVE.W  #7, D0
                LEA     (BKPTINS+8*2), A0
                MOVE    #BKPT0+7, D1
.NEXT           MOVE.W  D1, -(A0)
                SUBQ    #1, D1
                DBRA    D0, .NEXT
                MOVE.L  #PROG, CONTINUE
                MOVE.L  #$20, CONTSIZE
                MOVE.L  #USERSTACK, USERSP
                MOVE.L  #PROG, USERPC
                RTS

INITDUART       MOVEA.L #DUART, A6              ; A6 points at DUART base
                MOVE.B  #$00, IMR(A6)           ; Disable all interrupts
                MOVE.B  #$70, ACR(A6)           ; BRG Select = set 1
                MOVE.B  #$03, SOPB(A6)          ; Write $03 to Set Output Port Bits Command (Set OP2-OP7 high)
                MOVEQ   #$10, D0
                MOVE.B  D0, CRA(A6)             ; Write $10 to CRA Reset MR pointer to MRA1
                MOVE.B  D0, CRB(A6)             ; Write $10 to CRB Reset MR pointer to MRB1
                MOVE.B  #$93, MRA(A6)           ; Write $93 to MRA1 - RTS enabled, Error mode = BLOCK,  8 bits/char
                MOVE.B  #$93, MRB(A6)           ; Write $93 to MRB1 - Error mode = BLOCK,  8 bits/char
                MOVE.B  #$17, MRA(A6)           ; Write $17 to MRA2 - CTS Enable Tx,  1 stop bit
                MOVE.B  #$17, MRB(A6)           ; Write $17 to MRB2 - 1 stop bit
                MOVEQ   #$05, D0
                MOVE.B  D0, CRA(A6)             ; Write $05 to CRA - Enable Tx,  Enable Rx
                MOVE.B  D0, CRB(A6)             ; Write $05 to CRB - Enable Tx,  Enable Rx
                MOVEQ   #$CC, D1                ; 38.4k Baud
                MOVE.B  D1, CSRA(A6)            ; Write Baud rate to CSRA
                MOVE.B  D1, CSRB(A6)            ; Write Baud rate to CSRB
                RTS


; Get a line into the line buffer (user callable)
; Buffer pointer in A0, Buffer size in D2,
; Returns line length in D1, other registers are preserved
; Buffer is null terminated and requires at least one additional byte beyond the
; size to store the null if filled.
GETLINEUSR      MOVE.L D0, -(SP)
                BSR.S  GETLINEAUX
                MOVE.L (SP)+, D0
                RTS

; Get a line into the line buffer INBUF
; Returns line length in D1
; Buffer is null terminated
GETLINE         MOVEM.L D0/D2, -(SP)
                LEA     INBUF, A0
                MOVE.W  #INBUFSZ, D2
                BSR.S   GETLINEAUX
                MOVEM.L (SP)+, D0/D2
                RTS

; Common core for system and user line input
GETLINEAUX      MOVEQ   #0, D1
.NEXTCH         BSR.S   GETCH
                CMPI.B  #CR, D0                 ; Terminate on CR
                BEQ.S   .ENDL
                CMPI.B  #LF, D0                 ; Ignore LF
                BEQ.S   .NEXTCH
                CMPI.B  #DELETE, D0             ; Delete?
                BEQ.S   .NEXTCH                 ; Ignore
                CMPI.B  #BKSP, D0               ; Backspace?
                BNE.S   .SKIPCTRL               ; If not then check for other control characters
                TST.W   D1                      ; Backspace at start of line is ignored
                BEQ.S   .NEXTCH
                SUBI.W  #1, D1                  ; Drop a character in the buffer
                BSR.S   OUTCH                   ; Echo Backspace
                MOVE.B  #SPACE, D0              ; Then Space
                BSR.S   OUTCH
                MOVE.B  #BKSP, D0               ; Then Backspace
                BSR.S   OUTCH
                BRA.S   .NEXTCH
.SKIPCTRL       CMPI.B  #SPACE, D0              ; Ignore other control characters
                BLT.S   .NEXTCH
                CMP.W   D2, D1                  ; Buffer full?
                BGE.S   .NEXTCH                 ; Yup! Dump the character
                MOVE.B  D0, (A0, D1.W)          ; Store character in buffer
                ADDQ.W  #1, D1                  ; Bump the buffer offset
                BSR.S   OUTCH                   ; Echo the character
                BRA.S   .NEXTCH                 ; Back for more
.ENDL           MOVE.B  #0, (A0, D1.W)          ; Add a terminating zero
                BSR.W   CRLF                    ; New line on console
                RTS                             ; D1 contains the number of characters in the buffer

; Set D0.B if there is an input character waiting
CHRDY           BTST    #$00, DUART+SRA         ; Test SRA bit 0 - RxRdy
                SNE     D0                      ; Flag in D0
                RTS

; Get the next input character in DO
GETCH           BTST    #$00, DUART+SRA         ; Test SRA bit 0 - RxRdy
                BEQ.S   GETCH                   ; Loop until ready
                MOVE.B  DUART+TBA, D0           ; Get the input character
                RTS

; Send the character in D0
OUTCH           BTST    #$02, DUART+SRA         ; Test SRA bit 2 - TxRdy
                BEQ.S   OUTCH                   ; Loop until ready
                MOVE.B  D0, DUART+TBA           ; Send character
                RTS

; Send the null terminated string at A0 leaving A0 pointing at the next byte after the null
OUTS            MOVE.L  D0, -(SP)               ; Save D0
                BRA.S   .SKIP
.PCH            BSR.W   OUTCH
.SKIP           MOVE.B  (A0)+, D0
                BNE.S   .PCH
                MOVE.L  (SP)+, D0               ; Restore D0
                RTS

OUTSLN          BSR     OUTS
                BRA     CRLF

; Send the null terminated string at A0
; Print, at most, D1 characters leave A0 pointing after the last character output
; NOTE: A0 will never be left pointing at a terminating NULL
; D1 will remain decremented by the number of characters output + 1, not including the NULL
OUTSSAFE        MOVE.L  D0, -(SP)               ; Save D0
                BRA.S   .SKIP
.PCH            BSR.W   OUTCH
.SKIP           MOVE.B  (A0)+, D0
                DBNE    D1, .PCH
                CMPI    #0, (A0)
                BRA     .NOTNULL                ; Skip over NULL if we just missed it
                ADDA    #1, A0
.NOTNULL        MOVE.L  (SP)+, D0               ; Restore D0
                RTS

; Output a CR LF to start a new line
CRLF            MOVE.L  D0, -(SP)
                MOVE.B  #CR, D0
                BSR.W   OUTCH
                MOVE.B  #LF, D0
                BSR.W   OUTCH
                MOVE.L  (SP)+, D0
                RTS



; Print a single hex digit from the 4 LSBs of D0 - Destroys D0
PRHEXDIGIT      ANDI.B  #$F, D0                 ; Mask digit
                CMPI.B  #9, D0                  ; Convert
                BLE.S   .SKIP
                ADDI.B  #7, D0
.SKIP           ADDI.B  #'0', D0
                BSR.W   OUTCH                   ; Print hex digit
                RTS


; Print a hex byte in D0.B - All registers preserved
PRHEX2          MOVE.L  D0, -(SP)
                LSR.B   #4, D0
                BSR.S   PRHEXDIGIT
                MOVE.L  (SP), D0
                BSR.S   PRHEXDIGIT
                MOVE.L  (SP)+, D0
                RTS

; Print a hex word in D0.W - All registers preserved
PRHEX4          MOVE.L  D0, -(SP)
                LSR.W   #8, D0
                BSR.S   PRHEX2
                MOVE.L  (SP), D0
                BSR.S   PRHEX2
                MOVE.L  (SP)+, D0
                RTS

; Print a hex long word in D0.L - All registers preserved
PRHEX6          SWAP    D0
                BSR.S   PRHEX2
                SWAP    D0
                BSR.S   PRHEX4
                RTS
                
; Print a hex long word in D0.L - All registers preserved
PRHEX8          SWAP    D0
                BSR.S   PRHEX4
                SWAP    D0
                BSR.S   PRHEX4
                RTS

; Print D0.W in binary
PRBIN16         MOVEM.L D0-D2, -(SP)
                MOVE.W  D0, D2
                MOVE.W  #$0F, D1                ; 16 bits
.LOOP           MOVE.B  #$18, D0                ; 2 * $18 is an ASCII '0'
                LSL.W   #1, D2                  ; Add an extend bit and it becomes a '1'
                ADDX.B  D0, D0
                BSR.W   OUTCH
                DBRA    D1, .LOOP
                MOVEM.L (SP)+, D0-D2
                RTS
                
                ; Print D0.B in binary
PRBIN8          MOVEM.L D0-D2, -(SP)
                MOVE.W  D0, D2
                MOVE.W  #$07, D1                ; 8 bits
.LOOP           MOVE.B  #$18, D0                ; 2 * $18 is an ASCII '0'
                LSL.B   #1, D2                  ; Add an extend bit and it becomes a '1'
                ADDX.B  D0, D0
                BSR.W   OUTCH
                DBRA    D1, .LOOP
                MOVEM.L (SP)+, D0-D2
                RTS

; Decimal place values                
                DC.L    1
                DC.L    10
                DC.L    100
                DC.L    1000
                DC.L    10000
                DC.L    100000
                DC.L    1000000
                DC.L    10000000
                DC.L    100000000
                DC.L    1000000000
TENTAB

; Print D0 as signed decimal
PRSDEC          MOVEM.L D0-D2/A0, -(SP)
                MOVE.L  D0,D1
                BPL     PRDEC1
                MOVE.B  #'-', D0
                BSR     OUTCH
                NEG.L   D1
                BRA     PRDEC1
                
; Print D0 in decimal
PRDEC           MOVEM.L D0-D2/A0, -(SP)
                MOVE.L  D0,D1
PRDEC1          LEA.L   TENTAB, A0
                MOVE    #9,D2
.TENLOOP        CMP.L   -(A0), D1
                BHI     .DIGITS
                DBRA    D2, .TENLOOP
.DIGITS         MOVE.B  #'0', D0
                TST.L   D1
                BEQ     .ZEROES
.DIGLOOP        CMP.L   (A0), D1
                BLO     .PRDIG
                SUB.L   (A0), D1   
                ADDQ.B  #1,D0
                BRA     .DIGLOOP
.PRDIG          BSR     OUTCH
                SUBA    #4, A0
                TST     D2
                DBMI    D2, .DIGITS    ; D2 may already be -ve
.DONE           MOVEM.L (SP)+, D0-D2/A0
                RTS
.ZEROES         BSR     OUTCH
                DBRA    D2, .ZEROES
                BRA     .DONE
                
; Print D0 spaces
SPACES          MOVE.L  D1, -(SP)
                MOVE.W  D0, D1
                MOVEQ   #SPACE, D0
                BRA.S   .NEXT
.LOOP           BSR.W   OUTCH
.NEXT           DBRA    D1, .LOOP
                MOVE.L  (SP)+, D1
                RTS

; Dump registers and disassemble at PC
; Disassembles into INBUF
DUMPREGSDIS     BSR     DUMPREGSNPC                     
                LEA.L   PCLEGEND, A0            ; Print PC =
                BSR.W   OUTS
                MOVE.L  (USERPC), A4            ; Print PC and disassembly
                MOVE.L  (A4), D0
                MOVE.L  4(A4), D1
                MOVE.L  8(A4), D2
                LEA     INBUF, A5
                BSR     DCODE68K
                MOVEA.L A5, A0
                MOVE.B  #0, 1(A6)
                BSR     OUTSLN
                RTS

; Dump registers without disassembly
; Does not destroy INBUF or registers           
DUMPREGS        MOVEM.L D0-D1/A0-A1, -(SP)
                BSR     DUMPREGSNPC                     
                LEA.L   PCLEGEND, A0            ; Print PC =
                BSR.W   OUTS
                MOVE.L  (USERPC), D0            ; Print PC
                BSR.W   PRHEX8
                BSR.W   CRLF
                MOVEM.L (SP)+, D0-D1/A0-A1
                RTS
                        
; Dump the User mode registers without the PC
DUMPREGSNPC     MOVEQ   #0, D1                  ; Register index
                LEA     USERD0, A1
.NEXT           BSR.S   DUMPREG                 ; Dump one address or data register
                ADDI    #1, D1
                MOVE.B  D1, D0
                ANDI.B  #3, D0
                BNE.S   .NEXT
                BSR.W   RHS                     ; Print the SR and PC on the RHS
                BSR.W   CRLF
                CMPI.B  #$10, D1                ; Do all 16
                BLT.S   .NEXT
                RTS

;D1 is an index into the User Registers
DUMPREG         MOVEQ   #2, D0
                BSR.W   SPACES
                MOVE.B  #'D', D0
                CMPI.B  #8, D1
                BLT.S   .DREG
                MOVE.B  #'A', D0
.DREG           BSR.W   OUTCH
                MOVE.B  D1, D0
                ANDI.B  #7, D0
                BSR.W   PRHEXDIGIT
                MOVE.B  #' ', D0
                BSR.W   OUTCH
                MOVE.B  #'=', D0
                BSR.W   OUTCH
                MOVE.B  #' ', D0
                BSR.W   OUTCH
                MOVE.W  D1, D0
                LSL.W   #2, D0
                MOVE.L  (A1, D0.W), D0
                BSR.W   PRHEX8
                RTS

; Print the User SR and CCR on the right
; D0 is 4 * Row number
RHS             MOVE.L  D1, D0
                LSR.B   #2, D0
                SUBQ    #1, D0
                DBRA    D0, .LINE2
.LINE1          LEA.L   SRBITS, A0              ; Print the bit names
                BSR.W   OUTS
                RTS
.LINE2          DBRA    D0, .LINE3
                LEA.L   SRLEGEND, A0            ; Print SR =
                BSR.W   OUTS
                MOVE.W  USERSR, D0
                SWAP    D0
                BRA.W   PRBIN8                  ; Print SR in binary
.LINE3          DBRA    D0, .LINE4
                LEA.L   CCRBITS, A0             ; Print the bit names
                BSR.W   OUTS
                RTS
.LINE4          LEA.L   CCRLEGEND, A0           ; Print CCR =
                BSR.W   OUTS
                MOVE.W  USERSR, D0
                BRA.W   PRBIN8                  ; Print CCR in binary
.DONE           RTS

SRBITS          DC.B    '       T S  III', 0
CCRBITS         DC.B    '          XNZVC', 0
SRLEGEND        DC.B    '  SR = ', 0
CCRLEGEND       DC.B    ' CCR = ', 0
PCLEGEND        DC.B    '  PC = ', 0


; Dump memory from A1 for D1 bytes
DUMPMEM         MOVEM.L D0-D3, -(SP)
                SUBQ    #1, D1
                MOVEQ   #0, D3
                MOVE.L  A1, D0
                ANDI    #$FFFFFFFE, D0          ; Round to an even address
                MOVEA.L D0, A1
.LINE           BSR.W   PRHEX8                  ; Print the address
                MOVEQ   #4, D0
                BSR.W   SPACES
                MOVEQ   #7, D2                  ; Print 8 words
.LOOP           MOVE.W  (A1)+, D0
                BSR.W   PRHEX4
                MOVE.B  #' ', D0
                BSR.W   OUTCH
                DBRA    D2, .LOOP
                SUB.L   #$10, A1                ; Reset the memory pointer
                MOVEQ   #$F, D2
.LOOP2          MOVE.B  (A1)+, D0               ; Now print 16 ASCII characters
                BSR.S   PASCII
                DBRA    D2, .LOOP2
                BSR.W   CRLF
                ADDI.B  #1, D3
                ANDI.B  #7, D3
                BNE.S   .NOBRK
                BSR.W   CRLF
.NOBRK          MOVE.L  A1, D0
                SUBI.L  #$10, D1
                BCC.S   .LINE
                MOVEM.L (SP)+, D0-D3
                RTS

; Print a printable ASCII character, otherwise print a dot
PASCII          CMPI.B  #DELETE, D0
                BGE.S   .DOT
                CMPI.B  #SPACE, D0
                BLT.S   .DOT
                BRA.W   OUTCH
.DOT            MOVE.B  #'.', D0
                BRA.W   OUTCH

; Parse the numerical value at A0 until the next space or null
;       &10             = decimal 10
;       $FF             = hex FF
;       F06A            = hex F06A (default)
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
.OK             MOVEM.L (SP)+, D0/D2-D3
                RTS
.ERR            MOVE.B  #BADNUM, ERROR          ; Set error flag
                BRA     .OK

; Parse digit in D0 for numeric input
; All of [A-Za-z0-9] are parsed to a numeric digit value in D0.W
; Invalid digits return $FFFF and set the N flag in the CCR
PARSEDIG        ANDI    #$FF, D0                ; Zero out the high bits
                CMPI.B  #'0', D0                ; Must be at least '0'
                BMI.S   .NOT
                CMP     #'9', D0                ; If <= 9 then it's decimal
                BLE.S   .DEC
                ANDI.B  #~$20, D0               ; Convert to upper case
                SUB     #'A', D0                ; 'A' -> 0
                BMI     .NOT                    ; Reject lower
                CMP     #$5, D0                 ; Reject more than 5
                BGT     .NOT
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; User I/O routines using TRAP #0 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;          
TRAP0           BSR     SAVEUREGS
                CMP     (T0VECEND-T0VEC)/2, D0
                BHS     BADT0VEC
                ADD     D0, D0
                MOVE    T0VEC(PC,D0.W), D0      ; Get vector offset
                JMP     VBASE(PC,D0.W)          ; Jump to service routine
                NOP
                
T0VEC           DC.W    T0MONITOR-VBASE         ; 0 - Return to monitor
                DC.W    T0CHRDY-VBASE           ; 1 - Return D1.B = $FF if there is an input character, $00 otherwise
                DC.W    T0GETCH-VBASE           ; 2 - Wait for and return input character in D1.B
                DC.W    T0OUTCH-VBASE           ; 3 - Send character in D1.B                
                DC.W    T0OUTS-VBASE            ; 4 - Send null terminated string at A0
                DC.W    T0OUTSLN-VBASE          ; 5 - Send null terminated string at A0 followed by CRLF
                DC.W    T0SPACES-VBASE          ; 6 - Send D1.W spaces
                DC.W    T0HEXLED-VBASE          ; 7 - Write D1.B in hex to the 7-segment LED
                DC.W    T0LED-VBASE             ; 8 - Write D1.B directly to 7-segment LED
                DC.W    T0GETCHC-VBASE          ; 9 - If input char ready, return in D0 else return $00
T0VECEND        DS.W    0        
                
VBASE
T0MONITOR       BRA     CMDLOOP
T0CHRDY         BSR     CHRDY
                MOVE.B  D0, USERD1+3
                BRA     TRAP0DONE
T0GETCH         BSR     GETCH
                MOVE.B  D0, USERD1+3
                BRA     TRAP0DONE
T0OUTCH         MOVE.B  D1, D0
                BSR     OUTCH
                BRA     TRAP0DONE
T0OUTS          BSR     OUTS
                MOVE.L  A0, USERA0
                BRA     TRAP0DONE
T0OUTSLN        BSR     OUTSLN
                MOVE.L  A0, USERA0
                BRA     TRAP0DONE
T0SPACES        MOVE.W  D1, D0
                BSR     SPACES
                BRA     TRAP0DONE
T0HEXLED        MOVE.L  #DUART, A0
                MOVE.B  #$FE, SOPB(A0)
                AND     #$F, D1
                MOVE.B  LEDHEX(PC,D1.W), COPB(A0)
                BRA     TRAP0DONE
T0LED           MOVE.L  #DUART, A0
                MOVE.B  #$FE, SOPB(A0)
                AND     #$FE, D1
                MOVE.B  D1, COPB(A0)
                BRA     TRAP0DONE
T0GETCHC        BSR     CHRDY
                MOVE.B  D0, USERD0+3
                BEQ     TRAP0DONE               ; No character, return 0
                BSR     GETCH                   ; Get character
                MOVE.B  D0, USERD0+3
                BRA     TRAP0DONE
BADT0VEC        LEA     BADT0MSG, A0
                BSR     OUTSLN    
TRAP0DONE       MOVE    USP, A0
                MOVE.L  A0, USERSP
                MOVEM.L USERD0, D0-D7/A0-A6,    ; Restore registers
                RTE                             ; ...and return to user code
                
; Data to write to DUART output bits for hex digits
; Bit 0 is controlled by the Chan A RTS output and is unaffected
; by set/reset operations               
LEDHEX          DC.B    $7E                     ; 0         
                DC.B    $0C                     ; 1
                DC.B    $B6                     ; 2
                DC.B    $9E                     ; 3
                DC.B    $CC                     ; 4
                DC.B    $DA                     ; 5
                DC.B    $FA                     ; 6
                DC.B    $0E                     ; 7
                DC.B    $FE                     ; 8
                DC.B    $DE                     ; 9
                DC.B    $EE                     ; A
                DC.B    $F8                     ; b
                DC.B    $72                     ; C
                DC.B    $BC                     ; d
                DC.B    $F2                     ; E
                DC.B    $E2                     ; F
                
BADT0MSG        DC.B    'BAD TRAP#0 FUNCTION INDEX', 0
                DS.W    0
                
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Other exception service routines 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;  
                
UNKNOWN         BSR     SAVEUREGS
                LEA     DOHMSG, A1
                BRA     MSGNREGS
                
BUSERR          BSR     SAVEUREGS
                LEA     BUSMSG, A1
                BRA     MSGNREGS
                
ADDRERR         BSR     SAVEUREGS
                LEA     ADDRMSG, A1

MSGNREGS        BEQ     .USER                   ; Check supervisor mode
                LEA     SUPERMSG, A0
                BSR     OUTS
                MOVE.L  2(SP), D0
                BSR     PRHEX8
                MOVE    #2, D0
                BSR     SPACES
.USER           MOVE.L  A1, A0
                BSR     OUTSLN
                TST.B   M68010
                BEQ     .SKIPVEC
                LEA     VECTORMSG, A0
                BSR     OUTS
                MOVE    6(SP), D0               ; Get vector format & offset
                BSR     PRHEX4
                BSR     CRLF 
.SKIPVEC        BSR     DUMPREGS
                BRA     CMDLOOP


                
                
; Trace traps will only occur in user code
; A trace trap may occur when:
;  1) We are in trace mode
;     Save registers, dump registers and return to command line
; 
;  2) We have continued from a breakpoint
;     TRACEMODE flag is clear, install breakpoints and continue
;
;  3) Both of the above
;     Continue as 1)
;
; 
TRACE           BSR     SAVEUREGS
                MOVEA.L #STACK, SP              ; Clear exception stack frame
                BSR     DUMPREGSDIS
                BRA     TRACERPT

ILLEGAL         BSR     SAVEUREGS
                BNE     .SUPER
                MOVEA   USERPC, A0             ; Get faulted instruction into D3
                MOVE    -2(A0), D3
                BSR     SWAPBKPTS              ; Swap out the breakpoints
                MOVE    D3,D0
                AND     #~$7, D3               ; Test for BKPT instruction
                CMP     #BKPT0, D3             ; A breakpoint has been hit
                BEQ     .DOBKPT
                LEA     ILLMSG, A0
                BSR     OUTSLN
                BSR     DUMPREGS
                BRA     CMDLOOP
                
.DOBKPT         MOVEA   BKPTMSG, A0
                BSR     OUTS
                AND.B   #7, D0
                ADD.B   #'0', D0
                BSR     OUTCH
                BSR     CRLF          
                BSR     DUMPREGS
                BRA     CMDLOOP

; Illegal instruction trap in supervisor mode
.SUPER          CMP     #MOVECADR, 2(SP)        ; Is this the processor test?
                BEQ     M68000                  ; We detected an M68000
                LEA     SUPERMSG, A0
                BSR     OUTS
                LEA     ILLMSG, A0
                BSR     OUTSLN
                LEA     PCMSG, A0
                BSR     OUTS
                ADD     #2, SP
                MOVE.L  (SP)+, D0               ; Get faulted PC
                BSR     PRHEX8                  ; Display it
                BSR     CRLF
                BRA     CMDLOOP

; Save the user registers if the exception originated in user code
; Return Z=1 if saved or Z=0 if supervisor mode exception
; The exception frame is left on the stack
; A6 is not preserved
SAVEUREGS       BTST.B  #5, 4(SP)               ; Test the supervisor flag
                BNE     .DONE
                MOVEM.L D0-D7/A0-A6, USERD0     ; Save user mode registers
                MOVE    USP, A6
                MOVE.L  A6, USERSP
                MOVE    4(SP), USERSR           ; Reach over return address
                MOVE.L  6(SP), USERPC           ; to exeception frame
                MOVE    #4, CCR
.DONE           RTS

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

NMI             MOVEA.L #STACK, A7              ; Reset the stack
                BSR     INITDUART
                LEA     NMIMSG, A0              ; Print message
                BSR     OUTSLN
                BRA     CMDLOOP                 ; Re-enter command loop

VECTORMSG       DC.B    'FORMAT/OFFSET = ',0
BUSMSG          DC.B    'BUS ERROR', 0
ADDRMSG         DC.B    'ADDRESS ERROR', 0
ILLMSG          DC.B    'ILLEGAL INSTRUCTION EXCEPTION', 0
SUPERMSG        DC.B    'SUPERVISOR ', 0
BKPTMSG         DC.B    'BREAKPOINT ', 0
PCMSG           DC.B    'PC = ', 0
NMIMSG          DC.B    'AJBMON WARM START', 0
DOHMSG          DC.B    'DOH!', 0
                DS.W    0



HELLO           DC.B    '~~~~~~~~~~~~~~~~~~', CR, LF
                DC.B    'AJBMON for Tiny68k', CR, LF
                DC.B    '~~~~~~~~~~~~~~~~~~', 0

PROMPT          DC.B    '> ', 0

BOOTCPM         DC.B    'Copying CP/M 68K from Compact Flash...', 0
CRCCPM          DC.B    'Checksum is ',0
NOCPM           DC.B    'No valid CP/M code, command cancelled', 0
RUNCPM          DC.B    'CP/M-68K V1.3 COPYRIGHT (C) 1982, 1984, 1985 Digital Research', 0

                DS.W    0                       ; Move to even address

CMDTAB          DC.B    'HE'                    ; Execute user code
                DC.L    HELPCMD
                
                DC.B    'GO'                    ; Execute user code
                DC.L    GOCMD
                
                DC.B    'ST'                    ; Trace user code
                DC.L    STEPCMD

                DC.B    'DR'                    ; Dump Registers
                DC.L    DRCMD

                DC.B    'DM'                    ; Dump Memory
                DC.L    DMCMD
                
                DC.B    'MM'                    ; Modify Memory
                DC.L    MMCMD
                
                DC.B    'DI'                    ; Disassemble
                DC.L    DISASMCMD

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

*               DC.B    'AS'                    ; Assemble
*               DC.L    ASSEMCMD
                
                DC.B    'LS'                    ; Load s-records
                DC.L    SRECCMD
                
                
                DC.W    0

* Padded to 16 chars
ERRORTAB        DC.B    'BAD NUMBER', 0, 0, 0, 0, 0, 0
                DC.B    'BAD COMMAND', 0, 0, 0, 0, 0
                DC.B    'NOT WRITEABLE', 0, 0, 0
                DC.B    'S-RECORD ERROR', 0, 0
                DC.B    'CHECKSUM ERROR', 0, 0
                DS.W    0

HELPTXT         DC.B    'AJBMon commands', CR, LF
                DC.B    'HE        - Display help', CR, LF
                DC.B    'GO [addr] - Go from address in user mode', CR, LF
                DC.B    'ST [addr] - Step from address in user mode', CR, LF
                DC.B    'DR        - Dump registers', CR, LF
                DC.B    'DM [blk]  - Dump memory block', CR, LF
                DC.B    'MM [addr] - Modify memory with hex or "ASCII', CR, LF
                DC.B    'SR [word] - Display or update status register', CR, LF
                DC.B    'SP [addr] - Display or update stack pointer', CR, LF
                DC.B    'PC [addr] - Display or update program counter', CR, LF
                DC.B    'An [addr] - Display or update address register n', CR, LF
                DC.B    'Dn [data] - Display or update data register n', CR, LF
                DC.B    'Bn [addr] - Display or update breakpoint n', CR, LF
                DC.B    'BL        - List breakpoints', CR, LF
                DC.B    'DI [blk]  - Disassemble block', CR, LF
*               DC.B    'AS [addr] - Assemble into memory', CR, LF
                DC.B    'LS        - Load s-records into memory', CR, LF
                DC.B    'BO        - Boot CP/M68K', CR, LF

                DC.B    'Numeric inputs are hex by default but may be explictly $hex or &decimal', CR, LF
                DC.B    'Memory block [blk] may be from:to or from size', CR, LF
                DC.B    'Size will default to the previous size, from will default to continue', CR, LF
                DC.B    'When stepping, space or enter will step again, g or G will go', CR, LF
                DC.B    0
                DS.W    0
                
                INCLUDE 'DCODE68K.X68'

*               INCLUDE 'CODE68K.X68'

                END     START                   ; last line of source































































*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~8~
