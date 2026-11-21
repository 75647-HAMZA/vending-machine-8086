; ============================================================
;  VENDING MACHINE CONTROLLER  -  8086 Assembly (emu8086)
;  Course : Computer Organization & Assembly Language
;
;  Keys:  1-8  select item        A/B/C/D/E  insert Rs 1/2/5/10/20
;         X    cancel (refund)    O  operator mode (PIN = 1234)
;         Q    quit
;  Auto refund if user is idle for TIMEOUT seconds with balance > 0
; ============================================================
.model small
.stack 100h

.data
TIMEOUT  equ 15                      ; idle seconds before auto refund

; ---- item table (8 items, names are 10 chars each) ----
names   db 'Chips     ','Biscuit   ','Chocolate ','Juice     '
        db 'Cola      ','Water     ','Gum       ','Nuts      '
price   db 10,15,20,25,30,35,40,50
stock   db 5,5,5,5,5,5,5,5

; ---- coin tables (index 0..4 = Rs 1,2,5,10,20) ----
coinval db 1,2,5,10,20
coinqty db 5,5,5,5,5                 ; coins inside machine (incl. inserted)
insqty  db 0,0,0,0,0                 ; coins inserted by current user
chg     db 0,0,0,0,0                 ; coins chosen for change

pin     db '1234'
balance dw 0
sales   dw 0
chgamt  dw 0
lastsec db 0
msgptr  dw 0
redraw  db 1                         ; 1 = full screen must be redrawn

; ---- messages ('$' terminated) ----
m_title   db '===== VENDING MACHINE CONTROLLER =====',13,10,13,10,'$'
m_rs2     db '  Rs $'
m_stk     db '  Stock: $'
m_soldtag db '  SOLD OUT$'
m_help    db 13,10,' Coins: A=Rs1 B=Rs2 C=Rs5 D=Rs10 E=Rs20'
          db 13,10,' Keys : 1-8 Select, X Cancel, O Operator, Q Quit'
          db 13,10,13,10,'$'
m_bal     db ' Balance: Rs $'
m_stat    db ' Status : $'
m_blank   db 79 dup(' '),'$'

m_welcome db 'Insert coins and choose an item.$'
m_coin    db 'Coin accepted.$'
m_soldout db 'ERROR: Item is sold out.$'
m_nomoney db 'ERROR: Not enough money. Insert more coins.$'
m_wrong   db 'ERROR: Wrong key. Try again.$'
m_nothing db 'Nothing to cancel. Balance is zero.$'
m_thanks  db 'Thank you! Take your item.$'
m_opbusy  db 'Operator mode only when balance is zero. Press X first.$'
m_badpin  db 'Wrong PIN! Access denied.$'

m_cancel  db 'Transaction cancelled.$'
m_timeout db 'Timeout! No activity - money returned.$'
m_nochg   db 'Sorry, machine cannot give change - money returned.$'
m_quit    db 'Machine closing - money returned.$'
m_refund  db 'Refund: Rs $'
m_disp    db 'Item dispensed: $'
m_chg     db 'Change returned: Rs $'
m_press   db 13,10,'Press any key to continue...$'
m_bye     db 'Machine switched off. Goodbye.$'

m_pin     db '--- OPERATOR MODE ---',13,10,'Enter 4-digit PIN: $'
m_opmenu  db '--- OPERATOR MENU ---',13,10,13,10
          db ' 1. Refill all items (to 10)',13,10
          db ' 2. Refill all coins (to 10 each)',13,10
          db ' 3. View sales and stock',13,10
          db ' 4. Exit operator mode',13,10,13,10
          db ' Choose: $'
m_done    db 13,10,'Done.$'
m_rep     db '--- OPERATOR REPORT ---',13,10,13,10,'$'
m_tsales  db 'Total sales: Rs $'
m_coins   db 13,10,'Coins in machine:',13,10,'$'
m_rs      db '   Rs $'
m_x       db ' x $'

.code
; ============================================================
main proc
    mov ax, @data
    mov ds, ax
    mov es, ax
    call update_time
    mov msgptr, offset m_welcome

main_loop:
    call show_screen
    call get_key
    cmp al, 0
    jne m1
    jmp do_timeout

m1: cmp al, 'a'                      ; make letters upper case
    jb m2
    cmp al, 'z'
    ja m2
    sub al, 20h
m2: cmp al, '1'                      ; item keys 1-8
    jb m3
    cmp al, '8'
    ja m3
    sub al, '1'
    call buy_item
    jmp main_loop
m3: cmp al, 'A'                      ; coin keys A-E
    jb m4
    cmp al, 'E'
    ja m4
    sub al, 'A'
    call insert_coin
    jmp main_loop
m4: cmp al, 'X'
    jne m5
    call do_cancel
    jmp main_loop
m5: cmp al, 'O'
    jne m6
    call oper_mode
    jmp main_loop
m6: cmp al, 'Q'
    jne m7
    jmp do_quit
m7: mov msgptr, offset m_wrong       ; any other key = error
    jmp main_loop

do_timeout:
    mov dx, offset m_timeout
    call refund_all
    mov msgptr, offset m_welcome
    jmp main_loop

do_quit:
    cmp balance, 0
    je q1
    mov dx, offset m_quit
    call refund_all
q1: call clr_scr
    mov dx, offset m_bye
    call print_str
    mov ax, 4C00h
    int 21h
main endp

; ============================================================
; get_key : waits for a key. Returns AL = key,
;           or AL = 0 if TIMEOUT seconds passed with balance > 0
; ============================================================
get_key proc
    push bx
    push dx
    xor bx, bx                       ; BX = idle poll counter
gk_wait:
    mov ah, 1                        ; key available?
    int 16h
    jnz gk_have
    cmp balance, 0
    je gk_wait                       ; no money inside: no timeout needed
    inc bx
    cmp bl, 0
    jne gk_wait                      ; check the clock only every 256 polls
gk_chk:
    mov ah, 2Ch                      ; get time, DH = seconds
    int 21h
    mov al, dh
    sub al, lastsec
    jnb gk_ok
    add al, 60                       ; minute rolled over
gk_ok:
    cmp al, TIMEOUT
    jb gk_wait
    mov al, 0                        ; timeout signal
    pop dx
    pop bx
    ret
gk_have:
    mov ah, 0
    int 16h                          ; read the key (AL)
    call update_time                 ; activity -> restart timer
    pop dx
    pop bx
    ret
get_key endp

; update_time : lastsec = current seconds
update_time proc
    push ax
    push cx
    push dx
    mov ah, 2Ch
    int 21h
    mov lastsec, dh
    pop dx
    pop cx
    pop ax
    ret
update_time endp

; ============================================================
; insert_coin : AL = coin index 0..4
; ============================================================
insert_coin proc
    xor ah, ah
    mov si, ax
    mov al, coinval[si]
    xor ah, ah
    add balance, ax
    inc coinqty[si]
    inc insqty[si]
    mov msgptr, offset m_coin
    ret
insert_coin endp

; ============================================================
; buy_item : AL = item index 0..7
; ============================================================
buy_item proc
    xor ah, ah
    mov di, ax                       ; DI = item index
    cmp stock[di], 0
    jne bi1
    mov msgptr, offset m_soldout
    ret
bi1:
    mov al, price[di]
    xor ah, ah                       ; AX = price
    cmp balance, ax
    jae bi2
    mov msgptr, offset m_nomoney
    ret
bi2:
    mov bx, balance
    sub bx, ax                       ; BX = change to give
    mov chgamt, bx
    call make_change
    jnc bi3                          ; CF=0 -> change possible
    mov dx, offset m_nochg
    call refund_all
    mov msgptr, offset m_welcome
    ret
bi3:
    xor si, si                       ; take change coins out of machine
    mov cx, 5
bi4:
    mov al, chg[si]
    sub coinqty[si], al
    mov insqty[si], 0                ; inserted coins now belong to machine
    inc si
    loop bi4
    dec stock[di]
    mov al, price[di]
    xor ah, ah
    add sales, ax
    mov balance, 0
    call clr_scr
    mov dx, offset m_disp
    call print_str
    call print_name
    call nl
    mov dx, offset m_chg
    call print_str
    mov ax, chgamt
    call print_num
    call nl
    mov bx, offset chg
    call print_coins
    call wait_key
    mov msgptr, offset m_thanks
    ret
buy_item endp

; ============================================================
; make_change : BX = amount. Greedy (Rs20 down to Rs1) using coinqty.
; Output: chg[] filled. CF=0 success, CF=1 if exact change impossible.
; ============================================================
make_change proc
    push ax
    push cx
    push dx
    push si
    xor si, si
    mov cx, 5
mc0:
    mov chg[si], 0
    inc si
    loop mc0
    mov si, 4                        ; start with Rs 20
mc1:
    mov cl, coinval[si]
    xor ch, ch                       ; CX = coin value
    mov ax, bx
    xor dx, dx
    div cx                           ; AX = how many coins needed
    mov dl, coinqty[si]
    xor dh, dh                       ; DX = coins available
    cmp ax, dx
    jbe mc2
    mov ax, dx                       ; cannot use more than available
mc2:
    mov chg[si], al
    mul cx                           ; AX = count * value
    sub bx, ax
    dec si
    jns mc1
    cmp bx, 0
    jne mc_fail
    pop si
    pop dx
    pop cx
    pop ax
    clc
    ret
mc_fail:
    pop si
    pop dx
    pop cx
    pop ax
    stc
    ret
make_change endp

; ============================================================
; refund_all : DX = reason message. Returns exactly the coins inserted.
; ============================================================
refund_all proc
    push ax
    push bx
    push cx
    push si
    push dx
    call clr_scr
    pop dx
    call print_str
    call nl
    mov dx, offset m_refund
    call print_str
    mov ax, balance
    call print_num
    call nl
    mov bx, offset insqty
    call print_coins
    xor si, si
    mov cx, 5
rf1:
    mov al, insqty[si]
    sub coinqty[si], al
    mov insqty[si], 0
    inc si
    loop rf1
    mov balance, 0
    call wait_key
    pop si
    pop cx
    pop bx
    pop ax
    ret
refund_all endp

; ============================================================
; do_cancel : user pressed X
; ============================================================
do_cancel proc
    cmp balance, 0
    jne dc1
    mov msgptr, offset m_nothing
    ret
dc1:
    mov dx, offset m_cancel
    call refund_all
    mov msgptr, offset m_welcome
    ret
do_cancel endp

; ============================================================
; oper_mode : PIN protected operator menu
; ============================================================
oper_mode proc
    cmp balance, 0
    je op0
    mov msgptr, offset m_opbusy
    ret
op0:
    call clr_scr
    mov dx, offset m_pin
    call print_str
    xor si, si
    mov cx, 4
    mov bl, 0                        ; BL = 1 if any digit wrong
op1:
    mov ah, 8                        ; read key without echo
    int 21h
    cmp al, pin[si]
    je op2
    mov bl, 1
op2:
    mov dl, '*'
    call putc
    inc si
    loop op1
    call nl
    cmp bl, 0
    je op_menu
    mov dx, offset m_badpin
    call print_str
    call wait_key
    mov msgptr, offset m_badpin
    ret

op_menu:
    call clr_scr
    mov dx, offset m_opmenu
    call print_str
    mov ah, 8
    int 21h
    cmp al, '1'
    jne om2
    xor si, si                       ; refill items
    mov cx, 8
om1:
    mov stock[si], 10
    inc si
    loop om1
    jmp om_done
om2:
    cmp al, '2'
    jne om3
    xor si, si                       ; refill coins
    mov cx, 5
om2l:
    mov coinqty[si], 10
    inc si
    loop om2l
    jmp om_done
om3:
    cmp al, '3'
    jne om4
    call report
    jmp op_menu
om4:
    cmp al, '4'
    je om_exit
    jmp op_menu
om_done:
    mov dx, offset m_done
    call print_str
    call wait_key
    jmp op_menu
om_exit:
    mov msgptr, offset m_welcome
    ret
oper_mode endp

; report : total sales, stock per item, coins in machine
report proc
    call clr_scr
    mov dx, offset m_rep
    call print_str
    mov dx, offset m_tsales
    call print_str
    mov ax, sales
    call print_num
    call nl
    call nl
    xor di, di
rp1:
    mov dl, '['
    call putc
    mov ax, di
    add al, '1'
    mov dl, al
    call putc
    mov dl, ']'
    call putc
    mov dl, ' '
    call putc
    call print_name
    mov dx, offset m_stk
    call print_str
    mov al, stock[di]
    xor ah, ah
    call print_num
    call nl
    inc di
    cmp di, 8
    jae rp2
    jmp rp1
rp2:
    mov dx, offset m_coins
    call print_str
    mov bx, offset coinqty
    call print_coins
    call wait_key
    ret
report endp

; ============================================================
; show_screen : menu + balance + status
; ============================================================
show_screen proc
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    cmp redraw, 0
    jne ss_full
    jmp ss_dyn                       ; only update balance/status lines
ss_full:
    call clr_scr
    mov redraw, 0
    mov dx, offset m_title
    call print_str
    xor di, di
ss1:
    mov dl, ' '
    call putc
    mov dl, '['
    call putc
    mov ax, di
    add al, '1'
    mov dl, al
    call putc
    mov dl, ']'
    call putc
    mov dl, ' '
    call putc
    call print_name
    mov dx, offset m_rs2
    call print_str
    mov al, price[di]
    xor ah, ah
    call print_num
    mov dx, offset m_stk
    call print_str
    mov al, stock[di]
    xor ah, ah
    call print_num
    cmp stock[di], 0
    jne ss2
    mov dx, offset m_soldtag
    call print_str
ss2:
    call nl
    inc di
    cmp di, 8
    jae ss3
    jmp ss1
ss3:
    mov dx, offset m_help
    call print_str
ss_dyn:
    mov dh, 14                       ; balance line (row 14)
    mov dl, 0
    call set_cur
    mov dx, offset m_blank           ; erase old text
    call print_str
    mov dh, 14
    mov dl, 0
    call set_cur
    mov dx, offset m_bal
    call print_str
    mov ax, balance
    call print_num
    mov dh, 15                       ; status line (row 15)
    mov dl, 0
    call set_cur
    mov dx, offset m_blank
    call print_str
    mov dh, 15
    mov dl, 0
    call set_cur
    mov dx, offset m_stat
    call print_str
    mov dx, msgptr
    call print_str
    mov dh, 17
    mov dl, 0
    call set_cur
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
show_screen endp

; ============================================================
; Helper procedures
; ============================================================
; print_name : prints name of item DI (10 chars)
print_name proc
    push ax
    push bx
    push cx
    push dx
    mov ax, di
    mov cx, 10
    mul cx
    mov bx, offset names
    add bx, ax
    mov cx, 10
pn1:
    mov dl, [bx]
    call putc
    inc bx
    loop pn1
    pop dx
    pop cx
    pop bx
    pop ax
    ret
print_name endp

; print_coins : BX = 5-byte table. Prints "Rs V x N" for non-zero entries
print_coins proc
    push ax
    push bx
    push cx
    push dx
    push si
    xor si, si
pc1:
    mov al, [bx+si]
    cmp al, 0
    je pc2
    push ax
    mov dx, offset m_rs
    call print_str
    mov al, coinval[si]
    xor ah, ah
    call print_num
    mov dx, offset m_x
    call print_str
    pop ax
    xor ah, ah
    call print_num
    call nl
pc2:
    inc si
    cmp si, 5
    jb pc1
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
print_coins endp

; print_num : prints AX as unsigned decimal
print_num proc
    push ax
    push bx
    push cx
    push dx
    mov bx, 10
    xor cx, cx
pnm1:
    xor dx, dx
    div bx
    push dx
    inc cx
    cmp ax, 0
    jne pnm1
pnm2:
    pop dx
    add dl, '0'
    mov ah, 2
    int 21h
    loop pnm2
    pop dx
    pop cx
    pop bx
    pop ax
    ret
print_num endp

; print_str : prints '$' terminated string at DX
print_str proc
    push ax
    mov ah, 9
    int 21h
    pop ax
    ret
print_str endp

; putc : prints character in DL
putc proc
    push ax
    mov ah, 2
    int 21h
    pop ax
    ret
putc endp

; nl : new line
nl proc
    push dx
    mov dl, 13
    call putc
    mov dl, 10
    call putc
    pop dx
    ret
nl endp

; clr_scr : clear screen
clr_scr proc
    push ax
    mov ax, 3
    int 10h
    mov redraw, 1                    ; main screen is gone, redraw it later
    pop ax
    ret
clr_scr endp

; set_cur : move cursor to row DH, column DL
set_cur proc
    push ax
    push bx
    mov bh, 0
    mov ah, 2
    int 10h
    pop bx
    pop ax
    ret
set_cur endp

; wait_key : "Press any key" and wait
wait_key proc
    push ax
    push dx
    mov dx, offset m_press
    call print_str
    mov ah, 0
    int 16h
    call update_time
    pop dx
    pop ax
    ret
wait_key endp

end main
