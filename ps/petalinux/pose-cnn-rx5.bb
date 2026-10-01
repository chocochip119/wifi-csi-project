SUMMARY = "WiSensing RX5 pose CNN board bring-up test"
LICENSE = "CLOSED"

SRC_URI = "file://pose_cnn_rx5_board_test.c \
           file://pose_cnn_rx5_live.c \
           file://pose_cnn_regs.h \
           file://csi_pipeline.c \
           file://csi_pipeline.h \
           file://blob_rx5_test.bin \
           file://input_rx5_test.bin \
           file://pose_expected.bin \
           file://pose_expected.txt"

S = "${WORKDIR}"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} \
        -o pose_cnn_rx5_board_test pose_cnn_rx5_board_test.c
    ${CC} ${CFLAGS} ${LDFLAGS} -I${S} \
        -o pose_cnn_rx5_live csi_pipeline.c pose_cnn_rx5_live.c -lm
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 pose_cnn_rx5_board_test ${D}${bindir}/pose_cnn_rx5_board_test
    install -m 0755 pose_cnn_rx5_live ${D}${bindir}/pose_cnn_rx5_live

    install -d ${D}${datadir}/pose-cnn-rx5
    install -m 0644 blob_rx5_test.bin ${D}${datadir}/pose-cnn-rx5/blob_rx5_test.bin
    install -m 0644 input_rx5_test.bin ${D}${datadir}/pose-cnn-rx5/input_rx5_test.bin
    install -m 0644 pose_expected.bin ${D}${datadir}/pose-cnn-rx5/pose_expected.bin
    install -m 0644 pose_expected.txt ${D}${datadir}/pose-cnn-rx5/pose_expected.txt
}

FILES_${PN} += "${bindir}/pose_cnn_rx5_board_test \
                ${bindir}/pose_cnn_rx5_live \
                ${datadir}/pose-cnn-rx5/*"
