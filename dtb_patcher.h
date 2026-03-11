#ifndef DTB_PATCHER_H
#define DTB_PATCHER_H

// Check if the MiSTer_fb DTB region is patched for 16 MiB framebuffer.
// If not, patch the zImage_dtb and reboot.
void dtb_check_and_patch();

#endif
