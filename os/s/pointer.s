;----[ pointer.s ]----------------------

rdxy .macro ;Reads Ptr into X/Y
         ldx (\1)
         ldy (\1)+1
.endmacro

ldxy .macro ;Loads X/Y with address
         ldx #<(\1)
         ldy #>(\1)
.endmacro

stxy .macro
         stx (\1)
         sty (\1)+1
.endmacro

;---------------------------------------
;Get and Set RegPtr from Store

storeset .macro ;store,index
         stx (\1)+((\2)*2)
         sty (\1)+((\2)*2)+1
.endmacro

storeget .macro ;store,index
         ldx (\1)+((\2)*2)
         ldy (\1)+((\2)*2)+1
.endmacro

storewt .macro ;store
         ;A      -> index to write to
         ;RegPtr -> pointer to store
         sty hibyte+1
         asl a ;x2
         tay

         txa
         sta (\1),y
hibyte   lda #$ff
         sta (\1)+1,y
.endmacro

storerd .macro ;store
         ;A      -> index to read from
         ;RegPtr <- pointer from store
         asl a ;x2
         tay

         lda (\1),y
         tax
         lda (\1)+1,y
         tay
.endmacro

;---------------------------------------
;Toolkit Helpers

classmethod .macro ;method_offset
         jsr setclass_+stkt
         ldy #(\1)
         jsr getmethod_+stkt
.endmacro

supermethod .macro ;method_offset
         jsr setsuper_+stkt
         ldy #(\1)
         jsr getmethod_+stkt
.endmacro

;---------------------------------------
;Flag Manipulation

setflag .macro ;ptr,index,flags
         ldy #(\2)
         lda ((\1)),y
         ora #(\3)
         sta ((\1)),y
.endmacro

clrflag .macro ;ptr,index,flags
         ldy #(\2)
         lda ((\1)),y
         and #(\3)^$ff
         sta ((\1)),y
.endmacro

togflag .macro ;ptr,index,flags
         ldy #(\2)
         lda ((\1)),y
         eor #(\3)
         sta ((\1)),y
.endmacro

;---------------------------------------
;Setters and Getters

setobj8 .macro ;ptr,offset,int8
         ldy #(\2)
         lda #(\3)
         sta ((\1)),y
.endmacro

setobj16 .macro ;ptr,offset,int16
         ldy #(\2)
         lda #<(\3)
         sta ((\1)),y
         iny
         lda #>(\3)
         sta ((\1)),y
.endmacro

setobjptr .macro ;ptr,offset,ptr
         ldy #(\2)
         lda (\3)
         sta ((\1)),y
         iny
         lda (\3)+1
         sta ((\1)),y
.endmacro

setobjxy .macro ;ptr,offset,(RegWrd)
         tya
         ldy #(\2)+1
         sta ((\1)),y
         dey
         txa
         sta ((\1)),y
.endmacro

rdobj16 .macro ;ptr,offset
         ;RegPtr <- property
         ldy #(\2)
         lda ((\1)),y
         tax
         iny
         lda ((\1)),y
         tay
.endmacro

getobj16 .macro ;ptr,offset,to
         ;A <- property hi byte
         ldy #(\2)+1  ;offset hi byte
         lda ((\1)),y
         pha
         dey        ;offset lo byte
         lda ((\1)),y
         sta (\3)     ;Save lo byte
         pla
         sta (\3)+1   ;Save hi byte
.endmacro

;---------------------------------------

pushxy .macro
         tya ;Hi
         pha
         txa ;Lo
         pha
.endmacro

pullxy .macro
         pla
         tax ;Lo
         pla
         tay ;Hi
.endmacro

push16 .macro ;word to put on stack
         lda #>(\1) ;Hi
         pha
         lda #<(\1) ;Lo
         pha
.endmacro

pushptr .macro ;ptr to put on stack
         lda (\1)+1 ;Hi
         pha
         lda (\1)   ;Lo
         pha
.endmacro

pull16 .macro ;ptr to pull from stack
         pla
         sta (\1)   ;Lo
         pla
         sta (\1)+1 ;Hi
.endmacro

;---------------------------------------

copy16 .macro ;word,dest
         lda #<(\1)
         sta (\2)   ;1st: lo byte
         lda #>(\1)
         sta (\2)+1 ;2nd: hi byte
.endmacro

copyptr .macro ;ptr,dest
         lda (\1)
         sta (\2)   ;1st: lo byte
         lda (\1)+1
         sta (\2)+1 ;2nd: hi byte
.endmacro