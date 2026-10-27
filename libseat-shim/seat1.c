#define _GNU_SOURCE

/*
 * libseat shim: forces libseat_seat_name() to return "seat1".
 *
 * Used with LD_PRELOAD on headless Sway so wlroots binds to seat1
 * instead of seat0 (which the noop backend defaults to).
 * This allows headless Sway to claim virtual input devices tagged
 * with ID_SEAT=seat1 while the host desktop compositor (GNOME/KDE)
 * remains isolated on seat0.
 */

const char *libseat_seat_name(void *seat) {
    (void)seat;
    return "seat1";
}

