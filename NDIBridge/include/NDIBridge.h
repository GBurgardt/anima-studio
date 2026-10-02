#include <stdint.h>
void *studio_ndi_create(void);
const char *studio_ndi_name(void *sender);
void studio_ndi_send(void *sender, uint8_t *data, int width, int height, int stride);
void studio_ndi_destroy(void *sender);
