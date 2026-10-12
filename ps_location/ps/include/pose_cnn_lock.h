#ifndef POSE_CNN_LOCK_H
#define POSE_CNN_LOCK_H

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

/** Acquire the shared advisory accelerator lock before any memory access.
 * Returns an open descriptor on success, or -1 when unavailable.
 * Keep the descriptor open through cleanup; never unlink the lock file.
 * Only programs using this lock participate in ownership enforcement.
 */
static int pose_cnn_lock_acquire(void)
{
    int fd = open("/run/pose-cnn-rx5.lock", O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    if (fd < 0) {
        fprintf(stderr, "cannot open CNN lock: %s\n", strerror(errno));
        return -1;
    }
    if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
        fprintf(stderr, "CNN lock unavailable (another app may be running): %s\n",
                strerror(errno));
        close(fd);
        return -1;
    }
    return fd;
}

#endif
