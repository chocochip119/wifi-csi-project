SUMMARY = "WiSensing RX5 pose CNN on PS (ARM software) + PS/PL benchmark"
LICENSE = "CLOSED"

SRC_URI = "file://pose_cnn_sw.c \
           file://pose_cnn_sw.h \
           file://pose_cnn_rx5_live_sw.c \
           file://pose_cnn_rx5_bench.c \
           file://pose_cnn_regs.h \
           file://pose_cnn_lock.h \
           file://csi_pipeline.c \
           file://csi_pipeline.h \
           file://wise_server.c \
           file://wise_server.h"

S = "${WORKDIR}"

# -O3 after ${CFLAGS} so it overrides the default -O2 (NEON flags come from the tune).
SW_OPT = "-O3"

do_compile() {
    ${CC} ${CFLAGS} ${SW_OPT} ${LDFLAGS} -I${S} \
        -o pose_cnn_rx5_live_sw csi_pipeline.c wise_server.c pose_cnn_sw.c \
        pose_cnn_rx5_live_sw.c -lm -pthread
    ${CC} ${CFLAGS} ${SW_OPT} ${LDFLAGS} -I${S} \
        -o pose_cnn_rx5_bench pose_cnn_sw.c pose_cnn_rx5_bench.c -lm -pthread
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 pose_cnn_rx5_live_sw ${D}${bindir}/pose_cnn_rx5_live_sw
    install -m 0755 pose_cnn_rx5_bench ${D}${bindir}/pose_cnn_rx5_bench
}

FILES_${PN} += "${bindir}/pose_cnn_rx5_live_sw ${bindir}/pose_cnn_rx5_bench"
