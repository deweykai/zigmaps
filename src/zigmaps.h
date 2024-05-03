#ifndef ZIGMAPS_H
#define ZIGMAPS_H

#if __cplusplus
extern "C" {
#endif

struct MapLayer;
typedef struct MapLayer MapLayer;

extern MapLayer *zigmaps_create(float width, float height, float center_x,
                                float center_y, float resolution);
extern void zigmaps_free(MapLayer *map);
extern float *zigmaps_at(MapLayer *map, float x, float y);
extern MapLayer *zigmaps_make_traverse(MapLayer *map);

#if __cplusplus
}
#endif

#endif
