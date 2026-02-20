;----[ branch16.s ]---------------------

;16-bit Short Branches

b_ifnull .macro ;ptr,branchLabel
         lda (\1)
         ora (\1)+1
         beq (\2)
.endmacro
b_ifset .macro ;ptr,branchLabel
         lda (\1)
         ora (\1)+1
         bne (\2)
.endmacro

;16-bit Long Branches

bl_ifnull .macro ;ptr,branchLabel
         lda (\1)
         ora (\1)+1
         bne *+3
         jmp (\2)
.endmacro
bl_ifset .macro ;ptr,branchLabel
         lda (\1)
         ora (\1)+1
         beq *+3
         jmp (\2)
.endmacro

;Long Branches

bcc_ .macro
         bcs *+5
         jmp (\1)
.endmacro

bcs_ .macro
         bcc *+5
         jmp (\1)
.endmacro

beq_ .macro
         bne *+5
         jmp (\1)
.endmacro

bne_ .macro
         beq *+5
         jmp (\1)
.endmacro

bmi_ .macro
         bpl *+5
         jmp (\1)
.endmacro

bpl_ .macro
         bmi *+5
         jmp (\1)
.endmacro

bvc_ .macro
         bvs *+5
         jmp (\1)
.endmacro

bvs_ .macro
         bvc *+5
         jmp (\1)
.endmacro