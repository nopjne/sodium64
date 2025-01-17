/*
    Copyright 2021-2023 Hydr8gon

    This file is part of sodium64.

    sodium64 is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published
    by the Free Software Foundation, either version 3 of the License,
    or (at your option) any later version.

    sodium64 is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
    General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with sodium64. If not, see <https://www.gnu.org/licenses/>.
*/

#include <regdef.h>

.globl fps_emulate
.globl fps_display
.globl frame_count

.globl ppu_event
.globl read_mpyl
.globl read_mpym
.globl read_mpyh
.globl read_rdvraml
.globl read_rdvramh
.globl read_rdnmi
.globl read_timeup
.globl read_hvbjoy
.globl write_inidisp
.globl write_obsel
.globl write_oamaddl
.globl write_oamaddh
.globl write_oamdata
.globl write_bgmode
.globl write_bg1sc
.globl write_bg2sc
.globl write_bg3sc
.globl write_bg4sc
.globl write_bg12nba
.globl write_bg34nba
.globl write_bg1hofs
.globl write_bg1vofs
.globl write_bg2hofs
.globl write_bg2vofs
.globl write_bg3hofs
.globl write_bg3vofs
.globl write_bg4hofs
.globl write_bg4vofs
.globl write_vmain
.globl write_vmaddl
.globl write_vmaddh
.globl write_vmdatal
.globl write_vmdatah
.globl write_m7sel
.globl write_m7a
.globl write_m7b
.globl write_m7c
.globl write_m7d
.globl write_m7x
.globl write_m7y
.globl write_cgadd
.globl write_cgdata
.globl write_tm
.globl write_ts
.globl write_coldata
.globl write_setini
.globl write_nmitimen
.globl write_vtimel
.globl write_vtimeh

.data

event_func:  .word vblank_start
section_ptr: .word 0xA037C000

.align 8
vram:       .byte  0:0x10000
vram_table: .byte  0:0x400
oam:        .byte  0:0x220
cgram:      .hword 0:0x100

fps_emulate: .byte 0x00
fps_display: .byte 0x00
frame_count: .byte 0x00
frame_done:  .byte 0x00
fb_border:   .byte 0x00
brightness:  .byte 0x00
vram_incl:   .byte 0x00
vram_inch:   .byte 0x00

vram_fetch: .hword 0x0000
oam_addr:   .hword 0x000
oam_lsb:    .byte  0x00
bg_old:     .byte  0x00
m7_old:     .byte  0x00
cg_lsb:     .byte  0x00

mpy:      .word  0x000000
coldata:  .hword 0x0000
vmadd:    .hword 0x0000
cgadd:    .hword 0x0000
vtime:    .hword 0x0000
tm:       .byte  0x00
ts:       .byte  0x00
nmitimen: .byte  0x00
rdnmi:    .byte  0x00
timeup:   .byte  0x00
hvbjoy:   .byte  0x00

// RSP values that are saved for each section (0x50 bytes)
obj_size:    .word  0x10100808
objcharbase: .hword 0x0000
oamadd:      .hword 0x0000
bgscrnbase:  .hword 0x0000:4
bgbaseofsh:  .hword 0x0000:4
bgbaseofsv:  .hword 0x0000:4
bgcharbase:  .hword 0x0000:4
bghofs:      .hword 0x0000:4
bgvofs:      .hword 0x0000:4
m7hofs:      .hword 0x0000
m7vofs:      .hword 0x0000
m7a:         .hword 0x0000
m7b:         .hword 0x0000
m7c:         .hword 0x0000
m7d:         .hword 0x0000
m7x:         .hword 0x0000
m7y:         .hword 0x0000
fill_color:  .hword 0x0000
force_blank: .byte  0x00
bg_mode:     .byte  0x00
sub_mask:    .byte  0x00
main_mask:   .byte  0x00
m7_nowrap:   .byte  0x00
split_line:  .byte  0x00

// Possible offsets for additional screens past the base
scrn_ofsh: .hword 0x0000, 0x0800, 0x0000, 0x0800
scrn_ofsv: .hword 0x0000, 0x0000, 0x0800, 0x1000

// Possible object sizes; bytes are small X, small Y, large X, large Y
obj_sizes:
    .word 0x08081010, 0x08082020, 0x08084040, 0x10102020
    .word 0x10104040, 0x20204040, 0x10202040, 0x10202020

// Possible address increments for VRAM access
vram_incrs: .byte 1, 32, 128, 128

.text

ppu_event:
    // Jump to the current PPU event function
    lw   t0, event_func
    jr   t0


vblank_start:
    // Set the V-blank and NMI flags
    lbu  t0, hvbjoy
    or   t0, t0, 0x80
    sb   t0, hvbjoy
    li   t0, 0x80
    sb   t0, rdnmi

    // Skip handling the frame if it was already done
    lbu  t0, frame_done
    bnez t0, skip_frame
    jal  rsp_frame
skip_frame:
    sb   zero, frame_done

    // Reload the OAM address
    lhu  t1, oamadd
    sll  t0, t1, 1
    andi t0, t0, 0x3FE
    sh   t0, oam_addr

    // Trigger an NMI if enabled
    lbu  t0, nmitimen
    andi t0, t0, 0x80 // NMI enable
    beqz t0, sched_end
    li   a1, 0
    jal  trigger_nmi

sched_end:
    // Schedule the V-blank end event
    li   a0, 341 * 37 * 4 // V-blank period
    la   a1, vblank_end
    j    sched_next


vblank_end:
    // Clear the V-blank and NMI flags
    lbu  t0, hvbjoy
    andi t0, t0, ~0x80 & 0xFF
    sb   t0, hvbjoy
    sb   zero, rdnmi

    // Trigger HDMA once per frame to at least initialize values
    jal  trigger_hdma

    // Schedule a V-count event if the time is valid
    // TODO: support V-count during V-blank
    lhu  t0, vtime
    bge  t0, 225, no_count
    li   t1, 341 * 4
    mult t0, t1
    mflo a0
    la   a1, vcount_irq
    j    sched_next

no_count:
    // Schedule the V-blank start event
    li   a0, 341 * 225 * 4
    la   a1, vblank_start
    j    sched_next


vcount_irq:
    // Trigger a V-count IRQ if enabled
    lbu  t0, nmitimen
    andi t0, t0, 0x20 // V-IRQ enable
    beqz t0, sched_start
    andi t1, s4, 0x04 // IRQ disable
    bnez t1, sched_start
    li   a1, 4
    jal  trigger_nmi

    // Set the V-count IRQ flag
    li   t0, 0x80
    sb   t0, timeup

    // Check if the section limit has been hit
    lw   t1, section_ptr
    andi t2, t1, 0x1FFF
    beq  t2, 0x50 * 7, sched_start

    // Make a new frame section at the V-count line
    lhu  a0, vtime
    jal  make_section

sched_start:
    // Schedule the V-blank start event
    lhu  t0, vtime
    li   t1, 225
    sub  t0, t1, t0
    li   t1, 341 * 4
    mult t0, t1
    mflo a0
    la   a1, vblank_start
    j    sched_next


make_section: // a0: line
    // Use the sub screen backdrop color if set; otherwise use the main color
    // Blending isn't implemented, but this fixes the backdrop in some cases
    lbu  t0, brightness
    lhu  t1, coldata
    li   t3, 0x0001 // Alpha
    bnez t1, set_backdrop
    lhu  t1, cgram

set_backdrop:
    // Apply brightness to the red component and shift for N64 format
    andi t2, t1, 0x1F
    mult t2, t0
    mflo t2
    srl  t2, t2, 4
    sll  t2, t2, 11
    or   t3, t3, t2

    // Apply brightness to the green component and shift for N64 format
    srl  t2, t1, 5
    andi t2, t2, 0x1F
    mult t2, t0
    mflo t2
    srl  t2, t2, 4
    sll  t2, t2, 6
    or   t3, t3, t2

    // Apply brightness to the blue component and shift for N64 format
    srl  t2, t1, 10
    andi t2, t2, 0x1F
    mult t2, t0
    mflo t2
    srl  t2, t2, 4
    sll  t2, t2, 1
    or   t3, t3, t2

    // Set the backdrop color and section bounds
    sh   t3, fill_color
    sb   a0, split_line

    // Copy values for a new frame section
    la   t0, obj_size
    lw   t1, section_ptr
    li   t2, 0x50
sect_loop:
    addi t2, t2, -4
    lw   t3, (t0)
    addi t0, t0, 4
    sw   t3, (t1)
    addi t1, t1, 4
    bnez t2, sect_loop
    sw   t1, section_ptr
    jr   ra


rsp_frame:
    // Wait until the RSP is finished rendering
    lw   t0, 0xA4040010 // SP_STATUS_REG
    andi t0, t0, 0x0001 // Halt
    beqz t0, rsp_frame

    // Push the return address to the stack
    addi sp, sp, -4
    sw   ra, 0(sp)

    // Draw the FPS counter on the finished frame
    lbu  t0, fps_toggle
    beqz t0, count_frame
    lbu  a0, fps_display
    li   a1, 24 * 560 + 44 * 2
    jal  draw_value

count_frame:
    // Increment the frame counters with VI interrupts disabled
    li   t0, 1 << 6     // Clear VI mask
    sw   t0, 0xA430000C // MI_INTR_MASK_REG
    lbu  t0, frame_count
    lbu  t1, fps_emulate
    addi t0, t0, 1
    sb   t0, frame_count
    addi t1, t1, 1
    sb   t1, fps_emulate
    li   t0, 1 << 7     // Set VI mask
    sw   t0, 0xA430000C // MI_INTR_MASK_REG

    // Set initial values for palette conversion
    lbu  t0, brightness
    la   t8, 0xA038C7F8
    li   t9, 0x1FE

update_dpal:
    // Move to the next palette color
    lhu  t1, cgram(t9)
    addi t9, t9, -2
    li   t3, 0x0001 // Alpha

    // Apply brightness to the red component and shift for N64 format
    andi t2, t1, 0x1F
    mult t2, t0
    mflo t2
    srl  t2, t2, 4
    sll  t2, t2, 11
    or   t3, t3, t2

    // Apply brightness to the green component and shift for N64 format
    srl  t2, t1, 5
    andi t2, t2, 0x1F
    mult t2, t0
    mflo t2
    srl  t2, t2, 4
    sll  t2, t2, 6
    or   t3, t3, t2

    // Apply brightness to the blue component and shift for N64 format
    srl  t2, t1, 10
    andi t2, t2, 0x1F
    mult t2, t0
    mflo t2
    srl  t2, t2, 4
    sll  t2, t2, 1
    or   t3, t3, t2

    // Update a value in the RDP's palette and loop until finished
    sll  t2, t3, 16
    or   t3, t3, t2
    sw   t3, 0(t8)
    sw   t3, 4(t8)
    addi t8, t8, -8
    bnez t9, update_dpal
    sd   zero, (t8) // Index 0

    // Update the RSP's copy of OAM in DMEM
    la   t0, oam
    la   t1, 0xA4000840
    li   t2, 0x220
oam_loop:
    addi t2, t2, -4
    lw   t3, (t0)
    addi t0, t0, 4
    sw   t3, (t1)
    addi t1, t1, 4
    bnez t2, oam_loop

    // Update the RSP's VRAM dirty table with bits that were set this frame
    la   t0, vram_table
    la   t1, 0xA4000440
    li   t2, 0x400
table_loop:
    addi t2, t2, -4
    lw   t3, (t0)
    lw   t4, (t1)
    sw   zero, (t0)
    addi t0, t0, 4
    or   t3, t3, t4
    sw   t3, (t1)
    addi t1, t1, 4
    bnez t2, table_loop

update_vram:
    // Update the RSP's copy of VRAM
    la   t0, vram
    la   t1, 0xA03F0000
    li   t2, 0x10000
    // Make sure the copy is an 8 byte multiple, before starting the 8byte optimized copy.
    andi t3, t2, 3
    beq  t3, 0, vram_loop
    addi t2, t2, -4
    lw   t3, (t0)
    addi t0, t0, 4
    sw   t3, (t1)
    addi t1, t1, 4
vram_loop:
    addi t2, t2, -8
    ld   t3, (t0)
    addi t0, t0, 8
    sd   t3, (t1)
    addi t1, t1, 8
    bnez t2, vram_loop

    // Make a final frame section based on the framebuffer border
    lbu  t0, fb_border
    xori t1, t0, 0x8
    sw   t1, 0xA4000FF4 // Framebuffer border
    sll  t0, t0, 1
    addi a0, t0, 223
    jal  make_section
    sb   zero, split_line

    // Reset and swap section pointers with the RSP
    li   t0, 0xA037E000
    blt  t1, t0, set_ptrs
    xori t0, t0, 0x2000
set_ptrs:
    sw   t0, section_ptr
    xori t0, t0, 0x2000
    sw   t0, 0xA4000FF8 // Section pointer

frame_wait:
    // Wait for a framebuffer to be available
    lbu  t0, frame_count
    beq  t0, 2, frame_wait

    // Unhalt the RSP so it can render the next frame
    li   t0, 0x0001     // Clear halt
    sw   t0, 0xA4040010 // SP_STATUS_REG

    // Pop the return address from the stack
    lw   ra, 0(sp)
    addi sp, sp, 4
    jr   ra


sched_next: // a0: cycles, a1: function
    // Update timers before cycles are adjusted
    jal  update_timers

    // Offset all cycle counts for the next event
    lw   t0, apu_cycle1
    lw   t1, apu_cycle2
    add  s5, s5, a0 // CPU
    add  s3, s3, a0 // APU
    add  a3, a3, a0 // DSP
    add  t0, t0, a0 // Timer 0/1
    add  t1, t1, a0 // Timer 2
    sw   t0, apu_cycle1
    sw   t1, apu_cycle2

    // Don't let the CPU run if it's halted
    andi t0, s4, 0x200 // Halted
    beqz t0, sched_done
    li   s5, 0

sched_done:
    // Set the next event, update overflows, and return to execution
    sw   a1, event_func
    la   ra, cpu_execute
    j    update_overflows


read_mpyl: // v0: value
    // Read the low byte of the signed multiply result
    lbu  v0, mpy + 3
    jr   ra


read_mpym: // v0: value
    // Read the middle byte of the signed multiply result
    lbu  v0, mpy + 2
    jr   ra


read_mpyh: // v0: value
    // Read the high byte of the signed multiply result
    lbu  v0, mpy + 1
    jr   ra


read_rdvraml: // v0: value
    // Read the low byte of the prefetched VRAM data
    lbu  v0, vram_fetch + 1
    lbu  t2, vram_incl
    beqz t2, vraml_end

    // Prefetch a new 16-bit value before increment
    lhu  t0, vmadd
    sll  t1, t0, 1
    lhu  t1, vram(t1)
    sh   t1, vram_fetch

    // Increment the VRAM address
    add  t0, t0, t2
    andi t0, t0, 0x7FFF
    sh   t0, vmadd
vraml_end:
    jr   ra


read_rdvramh: // v0: value
    // Read the low byte of the prefetched VRAM data
    lbu  v0, vram_fetch
    lbu  t2, vram_inch
    beqz t2, vramh_end

    // Prefetch a new 16-bit value before increment
    lhu  t0, vmadd
    sll  t1, t0, 1
    lhu  t1, vram(t1)
    sh   t1, vram_fetch

    // Increment the VRAM address
    add  t0, t0, t2
    andi t0, t0, 0x7FFF
    sh   t0, vmadd
vramh_end:
    jr   ra


read_rdnmi: // v0: value
    // Read from the RDNMI register, resetting its flag
    lbu  v0, rdnmi
    sb   zero, rdnmi
    jr   ra


read_timeup: // v0: value
    // Read from the TIMEUP register, resetting its flag
    lbu  v0, timeup
    sb   zero, timeup
    jr   ra


read_hvbjoy: // v0: value
    // Read from the HVBJOY register
    // TODO: Set H-blank flag based on timestamps
    lbu  v0, hvbjoy
    xori v0, v0, 0x40 // Toggle H-blank (hack)
    sb   v0, hvbjoy
    jr   ra


write_inidisp: // a1: value
    // Set the force blank bit
    andi t0, a1, 0x80
    sb   t0, force_blank

    // Some games use mid-frame events to achieve a longer V-blank period
    // If force blank is set after a certain line, handle the frame now
    beqz t0, set_bright
    lbu  t1, hvbjoy
    andi t1, t1, 0x80
    bnez t1, set_bright
    lbu  t1, split_line
    ble  t1, 210, set_bright
    sb   t0, frame_done
    b    rsp_frame

set_bright:
    // Set the master brightness
    andi t0, a1, 0x0F
    sgtu t1, t0, zero
    add  t0, t0, t1
    sb   t0, brightness
    jr   ra


write_obsel: // a1: value
    // Update the OBJ character base address in DMEM
    // TODO: use the gap setting
    andi t0, a1, 0x3
    sll  t0, t0, 14
    sh   t0, objcharbase

    // Update the OBJ small and large sizes in DMEM
    andi t0, a1, 0xE0
    srl  t0, t0, 3
    lw   t0, obj_sizes(t0)
    sw   t0, obj_size
    jr   ra


write_oamaddl: // a1: value
    // Set the low byte of the OAM address reload
    lhu  t0, oamadd
    andi t1, a1, 0x00FF
    andi t0, t0, 0x8100
    or   t0, t0, t1
    sh   t0, oamadd

    // Reload the OAM address
    sll  t0, t0, 1
    andi t0, t0, 0x3FE
    sh   t0, oam_addr
    jr   ra


write_oamaddh: // a1: value
    // Set the high bits of the OAM address reload
    lhu  t0, oamadd
    sll  t1, a1, 8
    andi t1, t1, 0x8100
    andi t0, t0, 0x00FF
    or   t0, t0, t1
    sh   t0, oamadd

    // Reload the OAM address
    sll  t0, t0, 1
    andi t0, t0, 0x3FE
    sh   t0, oam_addr
    jr   ra


write_oamdata: // a1: value
    // Increment the OAM address, wrapping around on overflow
    lhu  t0, oam_addr
    blt  t0, 0x220, no_wrap
    addi t0, t0, -0x220
no_wrap:
    addi t1, t0, 1
    sh   t1, oam_addr

    // Check if writing to the last 32 bytes, otherwise check for first/second access
    andi t1, t0, 0x200
    bnez t1, oam_end
    andi t1, t0, 1
    bnez t1, oam_high

    // Save the low byte on first access
    sb   a1, oam_lsb
    jr   ra

oam_high:
    // Form a 16-bit value with the low byte and store it in OAM
    andi t0, t0, 0x3FF & ~1
    lbu  t1, oam_lsb
    sll  t2, a1, 8
    or   t3, t1, t2
    sh   t3, oam(t0)
    jr   ra

oam_end:
    // Store an 8-bit value in the last 32 bytes of OAM
    sb   a1, oam(t0)
    jr   ra


write_bgmode: // a1: value
    // Set the BG screen mode from 0 to 7
    // TODO: use the tile sizes
    andi t0, a1, 0x0F
    beq  t0, 0x09, high_prio
    andi t0, t0, 0x07
    sb   t0, bg_mode
    jr   ra

high_prio:
    // Set a special mode when mode 1 is set with the BG3 priority bit
    li   t0, 8
    sb   t0, bg_mode
    jr   ra


write_bg1sc: // a1: value
    // Update BG1's screen base address in DMEM
    andi t0, a1, 0x7C
    sll  t0, t0, 9
    sh   t0, bgscrnbase + 0

    // Update BG1's horizontal base offset in DMEM
    andi t1, a1, 0x03
    sll  t1, t1, 1
    lhu  t0, scrn_ofsh(t1)
    sh   t0, bgbaseofsh + 0

    // Update BG1's vertical base offset in DMEM
    lhu  t0, scrn_ofsv(t1)
    sh   t0, bgbaseofsv + 0
    jr   ra


write_bg2sc: // a1: value
    // Update BG2's screen base address in DMEM
    andi t0, a1, 0x7C
    sll  t0, t0, 9
    sh   t0, bgscrnbase + 2

    // Update BG2's horizontal base offset in DMEM
    andi t1, a1, 0x03
    sll  t1, t1, 1
    lhu  t0, scrn_ofsh(t1)
    sh   t0, bgbaseofsh + 2

    // Update BG2's vertical base offset in DMEM
    lhu  t0, scrn_ofsv(t1)
    sh   t0, bgbaseofsv + 2
    jr   ra


write_bg3sc: // a1: value
    // Update BG3's screen base address in DMEM
    andi t0, a1, 0x7C
    sll  t0, t0, 9
    sh   t0, bgscrnbase + 4

    // Update BG3's horizontal base offset in DMEM
    andi t1, a1, 0x03
    sll  t1, t1, 1
    lhu  t0, scrn_ofsh(t1)
    sh   t0, bgbaseofsh + 4

    // Update BG3's vertical base offset in DMEM
    lhu  t0, scrn_ofsv(t1)
    sh   t0, bgbaseofsv + 4
    jr   ra


write_bg4sc: // a1: value
    // Update BG4's screen base address in DMEM
    andi t0, a1, 0x7C
    sll  t0, t0, 9
    sh   t0, bgscrnbase + 6

    // Update BG4's horizontal base offset in DMEM
    andi t1, a1, 0x03
    sll  t1, t1, 1
    lhu  t0, scrn_ofsh(t1)
    sh   t0, bgbaseofsh + 6

    // Update BG4's vertical base offset in DMEM
    lhu  t0, scrn_ofsv(t1)
    sh   t0, bgbaseofsv + 6
    jr   ra


write_bg12nba: // a1: value
    // Update BG1's character base address in DMEM
    andi t0, a1, 0x07
    sll  t0, t0, 13
    sh   t0, bgcharbase + 0

    // Update BG2's character base address in DMEM
    andi t0, a1, 0x70
    sll  t0, t0, 9
    sh   t0, bgcharbase + 2
    jr   ra


write_bg34nba: // a1: value
    // Update BG3's character base address in DMEM
    andi t0, a1, 0x07
    sll  t0, t0, 13
    sh   t0, bgcharbase + 4

    // Update BG4's character base address in DMEM
    andi t0, a1, 0x70
    sll  t0, t0, 9
    sh   t0, bgcharbase + 6
    jr   ra


write_bg1hofs: // a1: value
    // Update BG1HOFS in DMEM with a 10-bit value from the old and new bytes
    lbu  t0, bg_old
    andi t1, a1, 0x3
    sll  t1, t1, 8
    or   t0, t0, t1
    sb   a1, bg_old
    sh   t0, bghofs + 0

    // Update M7HOFS with a 13-bit value from the old and new bytes
    lbu  t0, m7_old
    sll  t1, a1, 8
    or   t0, t0, t1
    sb   a1, m7_old
    sll  t0, t0, 18
    sra  t0, t0, 18
    sh   t0, m7hofs
    jr   ra


write_bg1vofs: // a1: value
    // Update BG1VOFS in DMEM with a 10-bit value from the old and new bytes
    lbu  t0, bg_old
    andi t1, a1, 0x3
    sll  t1, t1, 8
    or   t0, t0, t1
    sb   a1, bg_old
    sh   t0, bgvofs + 0

    // Update M7VOFS with a 13-bit value from the old and new bytes
    lbu  t0, m7_old
    sll  t1, a1, 8
    or   t0, t0, t1
    sb   a1, m7_old
    sll  t0, t0, 18
    sra  t0, t0, 18
    sh   t0, m7vofs
    jr   ra


write_bg2hofs: // a1: value
    // Update BG2HOFS in DMEM with a 10-bit value from the old and new bytes
    lbu  t0, bg_old
    andi t1, a1, 0x3
    sll  t1, t1, 8
    or   t0, t0, t1
    sb   a1, bg_old
    sh   t0, bghofs + 2
    jr   ra


write_bg2vofs: // a1: value
    // Update BG2VOFS in DMEM with a 10-bit value from the old and new bytes
    lbu  t0, bg_old
    andi t1, a1, 0x3
    sll  t1, t1, 8
    or   t0, t0, t1
    sb   a1, bg_old
    sh   t0, bgvofs + 2
    jr   ra


write_bg3hofs: // a1: value
    // Update BG3HOFS in DMEM with a 10-bit value from the old and new bytes
    lbu  t0, bg_old
    andi t1, a1, 0x3
    sll  t1, t1, 8
    or   t0, t0, t1
    sb   a1, bg_old
    sh   t0, bghofs + 4
    jr   ra


write_bg3vofs: // a1: value
    // Update BG3VOFS in DMEM with a 10-bit value from the old and new bytes
    lbu  t0, bg_old
    andi t1, a1, 0x3
    sll  t1, t1, 8
    or   t0, t0, t1
    sb   a1, bg_old
    sh   t0, bgvofs + 4
    jr   ra


write_bg4hofs: // a1: value
    // Update BG4HOFS in DMEM with a 10-bit value from the old and new bytes
    lbu  t0, bg_old
    andi t1, a1, 0x3
    sll  t1, t1, 8
    or   t0, t0, t1
    sb   a1, bg_old
    sh   t0, bghofs + 6
    jr   ra


write_bg4vofs: // a1: value
    // Update BG4VOFS in DMEM with a 10-bit value from the old and new bytes
    lbu  t0, bg_old
    andi t1, a1, 0x3
    sll  t1, t1, 8
    or   t0, t0, t1
    sb   a1, bg_old
    sh   t0, bgvofs + 6
    jr   ra


write_vmain: // a1: value
    // Get the VRAM increment and check if it applies to high or low access
    // TODO: address translation
    andi t0, a1, 0x03
    lbu  t0, vram_incrs(t0)
    andi t1, a1, 0x80
    bnez t1, vmain_high

    // Set the VRAM increment for low access
    sb   t0, vram_incl
    sb   zero, vram_inch
    jr   ra

vmain_high:
    // Set the VRAM increment for high access
    sb   zero, vram_incl
    sb   t0, vram_inch
    jr   ra


write_vmaddl: // a1: value
    // Set the low byte of the VRAM address
    sb   a1, vmadd + 1

    // Prefetch a 16-bit value for reading
    lhu  t0, vmadd
    sll  t1, t0, 1
    lhu  t0, vram(t1)
    sh   t0, vram_fetch
    jr   ra


write_vmaddh: // a1: value
    // Set the high byte of the VRAM address
    andi t0, a1, 0x7F
    sb   t0, vmadd

    // Prefetch a 16-bit value for reading
    lhu  t0, vmadd
    sll  t1, t0, 1
    lhu  t0, vram(t1)
    sh   t0, vram_fetch
    jr   ra


write_vmdatal: // a1: value
    // Write to the low VRAM byte at the current address
    lhu  t0, vmadd
    sll  t1, t0, 1
    sb   a1, 1 + vram(t1)

    // Set each layer's dirty bit for the modified VRAM block
    srl  t1, t1, 6
    li   t2, 0x1F
    sb   t2, vram_table(t1)

    // Increment the VRAM address
    lbu  t1, vram_incl
    add  t0, t0, t1
    andi t0, t0, 0x7FFF
    sh   t0, vmadd
    jr   ra


write_vmdatah: // a1: value
    // Write to the high VRAM byte at the current address
    lhu  t0, vmadd
    sll  t1, t0, 1
    sb   a1, vram(t1)

    // Set each layer's dirty bit for the modified VRAM block
    srl  t1, t1, 6
    li   t2, 0x1F
    sb   t2, vram_table(t1)

    // Increment the VRAM address
    lbu  t1, vram_inch
    add  t0, t0, t1
    andi t0, t0, 0x7FFF
    sh   t0, vmadd
    jr   ra


write_m7sel: // a1: value
    // Set whether mode 7 should wrap out of bounds or not
    // TODO: use the rest of the bits
    srl  t0, a1, 7
    sb   t0, m7_nowrap
    jr   ra


write_m7a: // a1: value
    // Update M7A with a 16-bit value from the old and new bytes
    lbu  t0, m7_old
    sll  t1, a1, 8
    or   t0, t0, t1
    sb   a1, m7_old
    sh   t0, m7a

    // Update the signed multiply result
    lh   t0, m7a
    lb   t1, m7b
    mult t0, t1
    mflo t0
    sw   t0, mpy
    jr   ra


write_m7b: // a1: value
    // Update M7B with a 16-bit value from the old and new bytes
    lbu  t0, m7_old
    sll  t1, a1, 8
    or   t0, t0, t1
    sb   a1, m7_old
    sh   t0, m7b

    // Update the signed multiply result
    lh   t0, m7a
    lb   t1, m7b
    mult t0, t1
    mflo t0
    sw   t0, mpy
    jr   ra


write_m7c: // a1: value
    // Update M7C with a 16-bit value from the old and new bytes
    lbu  t0, m7_old
    sll  t1, a1, 8
    or   t0, t0, t1
    sb   a1, m7_old
    sh   t0, m7c
    jr   ra


write_m7d: // a1: value
    // Update M7D with a 16-bit value from the old and new bytes
    lbu  t0, m7_old
    sll  t1, a1, 8
    or   t0, t0, t1
    sb   a1, m7_old
    sh   t0, m7d
    jr   ra


write_m7x: // a1: value
    // Update M7X with a 13-bit value from the old and new bytes
    lbu  t0, m7_old
    sll  t1, a1, 8
    or   t0, t0, t1
    sb   a1, m7_old
    sll  t0, t0, 18
    sra  t0, t0, 18
    sh   t0, m7x
    jr   ra


write_m7y: // a1: value
    // Update M7Y with a 13-bit value from the old and new bytes
    lbu  t0, m7_old
    sll  t1, a1, 8
    or   t0, t0, t1
    sb   a1, m7_old
    sll  t0, t0, 18
    sra  t0, t0, 18
    sh   t0, m7y
    jr   ra


write_cgadd: // a1: value
    // Set the palette address, resetting to first access
    sll  t0, a1, 1
    sh   t0, cgadd
    jr   ra


write_cgdata: // a1: value
    // Increment the palette address and check bit 0 for first/second access
    lhu  t0, cgadd
    addi t1, t0, 1
    sh   t1, cgadd
    andi t1, t0, 1
    bnez t1, cg_high

    // Save the low byte on first access
    sb   a1, cg_lsb
    jr   ra

cg_high:
    // Form a 16-bit value with the low byte and write it to CGRAM
    andi t0, t0, 0x1FF & ~1
    lbu  t1, cg_lsb
    sll  t2, a1, 8
    or   t1, t1, t2
    sh   t1, cgram(t0)
    jr   ra


write_tm: // a1: value
    // Set the main screen layer mask and mask out layers on the sub screen
    sb   a1, tm
    lbu  t0, ts
    xori t1, a1, 0x1F
    sb   a1, main_mask
    and  t0, t0, t1
    sb   t0, sub_mask
    jr   ra


write_ts: // a1: value
    // Set the sub screen layer mask with main layers masked out
    sb   a1, ts
    lbu  t0, tm
    xori t0, t0, 0x1F
    and  t0, t0, a1
    sb   t0, sub_mask
    jr   ra


write_coldata: // a1: value
    // Prepare to update the sub screen background color
    lhu  t0, coldata
    andi t1, a1, 0x1F // Intensity
    li   t2, 0x1F     // Mask
    li   t3, 3        // Count

next_channel:
    // Update a channel's intensity if its bit is set
    sll  t4, a1, t3
    andi t4, t4, 0x100
    beqz t4, skip_channel
    not  t4, t2
    and  t0, t0, t4
    or   t0, t0, t1

skip_channel:
    // Move to the next of the RGB channels
    sll  t1, t1, 5
    sll  t2, t2, 5
    addi t3, t3, -1
    bnez t3, next_channel
    sh   t0, coldata
    jr   ra


write_setini: // a1: value
    // Set an 8-pixel border if 224-line mode is set
    // TODO: use the rest of the bits
    andi t0, a1, 0x4
    sll  t0, t0, 1
    sb   t0, fb_border
    jr   ra


write_nmitimen: // a1: value
    // Write to the NMITIMEN register
    sb   a1, nmitimen
    jr   ra


write_vtimel: // a1: value
    // Write the low byte of the V-count timer value
    sb   a1, vtime + 1
skip_event:
    jr   ra


write_vtimeh: // a1: value
    // Write the high bit of the V-count timer value
    andi t0, 0x01
    sb   t0, vtime

    // Check if a V-count event can be scheduled
    lw   t0, event_func
    la   t1, vblank_start
    bne  t0, t1, skip_event

    // Calculate the cycles between V-blank and V-count
    lhu  t0, vtime
    li   t1, 225
    sub  t0, t1, t0
    blez t0, skip_event
    li   t1, 341 * 4
    mult t0, t1
    mflo t0
    bge  t0, s5, skip_event
    sub  a0, zero, t0

    // Update timers before cycles are adjusted
    move t8, ra
    jal  update_timers
    move ra, t8

    // Offset all cycle counts for the V-count event
    lw   t0, apu_cycle1
    lw   t1, apu_cycle2
    add  s5, s5, a0 // CPU
    add  s3, s3, a0 // APU
    add  a3, a3, a0 // DSP
    add  t0, t0, a0 // Timer 0/1
    add  t1, t1, a0 // Timer 2
    sw   t0, apu_cycle1
    sw   t1, apu_cycle2

    // Set the event function and update overflows
    la   t0, vcount_irq
    sw   t0, event_func
    j    update_overflows
