SUMMARY = "WiSensing RX5 pose CNN board bring-up test"
LICENSE = "CLOSED"

SRC_URI = "file://pose_cnn_rx5_board_test.c \
           file://pose_cnn_rx5_live.c \
           file://pose_cnn_regs.h \
           file://pose_cnn_lock.h \
           file://csi_pipeline.c \
           file://csi_pipeline.h \
           file://wise_server.c \
           file://wise_server.h \
           file://loc_ridge.c \
           file://loc_ridge.h \
           file://loc_ridge_rx5.bin \
           file://wisensing-autostart \
           file://wisensing-location.conf \
           file://pose_expected.txt"

# The repository does not bundle trained weights or board test inputs.
# install_app.sh optionally supplies this include with a complete asset directory.
include pose-cnn-rx5-vectors.inc
inherit update-rc.d
INITSCRIPT_NAME = "wisensing-autostart"
INITSCRIPT_PARAMS = "start 98 5 . stop 02 0 1 6 ."
S = "${WORKDIR}"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} \
        -o pose_cnn_rx5_board_test pose_cnn_rx5_board_test.c
    ${CC} ${CFLAGS} ${LDFLAGS} -I${S} \
        -o pose_cnn_rx5_live csi_pipeline.c wise_server.c loc_ridge.c pose_cnn_rx5_live.c -lm -pthread
}

do_install() {
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 wisensing-autostart ${D}${sysconfdir}/init.d/wisensing-autostart
    install -d ${D}${sysconfdir}/default
    install -m 0644 wisensing-location.conf ${D}${sysconfdir}/default/wisensing-location

    install -d ${D}${bindir}
    install -m 0755 pose_cnn_rx5_board_test ${D}${bindir}/pose_cnn_rx5_board_test
    install -m 0755 pose_cnn_rx5_live ${D}${bindir}/pose_cnn_rx5_live

    install -d ${D}${datadir}/pose-cnn-rx5
    for asset in blob_rx5_test.bin input_rx5_test.bin pose_expected.bin; do
        if [ -f "$asset" ]; then
            install -m 0644 "$asset" ${D}${datadir}/pose-cnn-rx5/"$asset"
        fi
    done
    install -m 0644 pose_expected.txt ${D}${datadir}/pose-cnn-rx5/pose_expected.txt
    # PS location Ridge model, exported by ps/tools/export_loc_model.py.
    install -m 0644 loc_ridge_rx5.bin ${D}${datadir}/pose-cnn-rx5/loc_ridge_rx5.bin
}

FILES_${PN} += "${bindir}/pose_cnn_rx5_board_test \
                ${bindir}/pose_cnn_rx5_live \
                ${datadir}/pose-cnn-rx5/*"

FILES_${PN} += "${sysconfdir}/init.d/wisensing-autostart ${sysconfdir}/default/wisensing-location"
CONFFILES_${PN} += "${sysconfdir}/default/wisensing-location"
