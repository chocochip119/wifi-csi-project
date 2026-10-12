/*
 * pose_cnn IP (user.org:user:pose_cnn:1.1, RX = 5) register map.
 * Block design: 20260930_cnn_soc / design_1, Zybo Z7-20, FCLK_CLK0 100 MHz.
 * All registers are 32-bit, little-endian, AXI4-Lite.
 */
#ifndef POSE_CNN_REGS_H
#define POSE_CNN_REGS_H

#include <stdint.h>

#define POSE_CNN_BASEADDR        0x43C00000u   /* S00_AXI, 64 KB window */

/* register offsets */
#define POSE_CNN_CONTROL         0x00u   /* W : write pulses (reads 0)                 */
#define POSE_CNN_STATUS          0x04u   /* R                                          */
#define POSE_CNN_CMD             0x08u   /* RW: 0 = INFER, 1 = LOAD                    */
#define POSE_CNN_INPUT_ADDR      0x0Cu   /* RW: physical address, 8-byte aligned       */
#define POSE_CNN_WEIGHT_ADDR     0x10u   /* RW: physical address, 8-byte aligned       */
#define POSE_CNN_OUTPUT_ADDR     0x14u   /* RW: physical address, 32-byte aligned      */
#define POSE_CNN_SCALE           0x18u   /* R : output scale, float32 bits (after LOAD) */

/* CONTROL bits (write 1 = one-cycle pulse) */
#define POSE_CNN_CTRL_START      (1u << 0)
#define POSE_CNN_CTRL_CLEAR      (1u << 1)   /* clears STATUS.done / STATUS.err_code */

/* STATUS bits */
#define POSE_CNN_ST_BUSY         (1u << 0)
#define POSE_CNN_ST_DONE         (1u << 1)
#define POSE_CNN_ST_ERROR        (1u << 2)
#define POSE_CNN_ST_CFG_OK       (1u << 3)   /* valid weights loaded */
#define POSE_CNN_ST_ERR_CODE(s)  (((s) >> 4) & 0xFu)

/* STATUS error codes */
#define POSE_CNN_ERR_NONE        0u
#define POSE_CNN_ERR_BAD_CMD     1u   /* CMD not 0/1                          */
#define POSE_CNN_ERR_NO_CFG      2u   /* INFER before a successful LOAD       */
#define POSE_CNN_ERR_BLOB        3u   /* blob header/size/shift check failed  */
#define POSE_CNN_ERR_MEM_RD      4u   /* DDR read error (RRESP/alignment)     */
#define POSE_CNN_ERR_MEM_WR      5u   /* DDR write error (BRESP/alignment)    */

/* commands */
#define POSE_CNN_CMD_INFER       0u
#define POSE_CNN_CMD_LOAD        1u

/* buffer sizes for RX = 5 */
#define POSE_CNN_RX              5
#define POSE_CNN_BLOB_BYTES      685136u   /* 5936 + RX*131072 + 23840 */
#define POSE_CNN_INPUT_BYTES     19200u    /* RX*3 ch x 128 x 10, int8 */
#define POSE_CNN_OUTPUT_BYTES    24u       /* 24 x int8                */
#define POSE_CNN_BLOB_MAGIC      0x36574C50u
#define POSE_CNN_BLOB_VERSION    2u
#define POSE_CNN_BLOB_WORDS      171284u   /* header word 2 (32-bit words) */

/* input layout: int8 in[ch][128][10], ch = rx + POSE_CNN_RX * ic  (rx 0..4, ic 0..2) */
#define POSE_CNN_IN_CH(rx, ic)   ((rx) + POSE_CNN_RX * (ic))

#endif /* POSE_CNN_REGS_H */
