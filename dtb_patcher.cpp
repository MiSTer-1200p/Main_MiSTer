#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "fpga_io.h"

#define ZIMAGE_PATH      "/media/fat/linux/zImage_dtb"
#define ZIMAGE_BACKUP    "/media/fat/linux/zImage_dtb.orig"
#define DTB_REG_PATH     "/proc/device-tree/MiSTer_fb/reg"
#define DTB_TMP_PATH     "/tmp/mister_fb.dtb"

// reg = <0x22000000 0x01000000> (16 MiB, patched)
static const uint8_t reg_16mib[] = { 0x22, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00 };

// Returns: 1 = already patched, 0 = needs patching, -1 = error
static int check_dtb()
{
	int fd = open(DTB_REG_PATH, O_RDONLY);
	if (fd < 0) return -1;

	uint8_t reg[8];
	ssize_t n = read(fd, reg, sizeof(reg));
	close(fd);

	if (n != (ssize_t)sizeof(reg)) return -1;

	if (!memcmp(reg, reg_16mib, 8)) return 1;

	return 0;
}

static int copy_file(const char *src, const char *dst)
{
	int fdin = open(src, O_RDONLY);
	if (fdin < 0) return -1;

	struct stat st;
	fstat(fdin, &st);

	int fdout = open(dst, O_WRONLY | O_CREAT | O_TRUNC, st.st_mode);
	if (fdout < 0) { close(fdin); return -1; }

	uint8_t buf[4096];
	ssize_t n;
	while ((n = read(fdin, buf, sizeof(buf))) > 0)
	{
		if (write(fdout, buf, n) != n) { close(fdin); close(fdout); return -1; }
	}

	close(fdin);
	close(fdout);
	return 0;
}

void dtb_check_and_patch()
{
	int status = check_dtb();
	if (status == 1)
	{
		printf("DTB: framebuffer already set to 16 MiB.\n");
		return;
	}
	if (status < 0)
	{
		printf("DTB: could not read %s, skipping patch.\n", DTB_REG_PATH);
		return;
	}

	printf("DTB: framebuffer is 8 MiB, patching to 16 MiB...\n");

	// Read zImage header to find DTB offset
	FILE *f = fopen(ZIMAGE_PATH, "rb");
	if (!f)
	{
		printf("DTB: could not open %s\n", ZIMAGE_PATH);
		return;
	}

	fseek(f, 0, SEEK_END);
	long file_size = ftell(f);

	// ARM zImage: offset 40 and 44 contain image start/end addresses
	uint32_t img_start, img_end;
	fseek(f, 40, SEEK_SET);
	if (fread(&img_start, 4, 1, f) != 1) { fclose(f); return; }
	fseek(f, 44, SEEK_SET);
	if (fread(&img_end, 4, 1, f) != 1) { fclose(f); return; }

	uint32_t dtb_offset = img_end - img_start;
	if (dtb_offset >= (uint32_t)file_size)
	{
		printf("DTB: invalid DTB offset in zImage header.\n");
		fclose(f);
		return;
	}

	// Extract DTB to temp file
	uint32_t dtb_size = file_size - dtb_offset;
	uint8_t *dtb = (uint8_t *)malloc(dtb_size);
	if (!dtb) { fclose(f); return; }

	fseek(f, dtb_offset, SEEK_SET);
	if (fread(dtb, 1, dtb_size, f) != dtb_size)
	{
		free(dtb);
		fclose(f);
		return;
	}
	fclose(f);

	FILE *tmp = fopen(DTB_TMP_PATH, "wb");
	if (!tmp) { free(dtb); return; }
	fwrite(dtb, 1, dtb_size, tmp);
	fclose(tmp);
	free(dtb);

	// Patch DTB using fdtput
	int ret = system("fdtput -t x " DTB_TMP_PATH " /MiSTer_fb reg 0x22000000 0x1000000");
	if (ret != 0)
	{
		printf("DTB: fdtput failed.\n");
		unlink(DTB_TMP_PATH);
		return;
	}

	// Backup original zImage
	printf("DTB: backing up %s to %s\n", ZIMAGE_PATH, ZIMAGE_BACKUP);
	if (copy_file(ZIMAGE_PATH, ZIMAGE_BACKUP) < 0)
	{
		printf("DTB: backup failed, aborting.\n");
		unlink(DTB_TMP_PATH);
		return;
	}

	// Write patched DTB back into zImage
	f = fopen(DTB_TMP_PATH, "rb");
	if (!f) { unlink(DTB_TMP_PATH); return; }

	fseek(f, 0, SEEK_END);
	long patched_size = ftell(f);
	fseek(f, 0, SEEK_SET);

	uint8_t *patched = (uint8_t *)malloc(patched_size);
	if (!patched) { fclose(f); unlink(DTB_TMP_PATH); return; }
	fread(patched, 1, patched_size, f);
	fclose(f);
	unlink(DTB_TMP_PATH);

	f = fopen(ZIMAGE_PATH, "r+b");
	if (!f)
	{
		printf("DTB: could not open %s for writing.\n", ZIMAGE_PATH);
		free(patched);
		return;
	}

	fseek(f, dtb_offset, SEEK_SET);
	if (fwrite(patched, 1, patched_size, f) != (size_t)patched_size)
	{
		printf("DTB: write failed.\n");
		fclose(f);
		free(patched);
		return;
	}

	fclose(f);
	free(patched);

	printf("DTB: patched successfully. Rebooting...\n");
	reboot(0);
}
