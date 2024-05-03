#ifndef ZIGMAPS_H
#define ZIGMAPS_H

struct MapLayer;

extern struct MapLayer *zigmaps_create(float const width, float const height,
                                       float const center_x,
                                       float const center_y,
                                       float const resolution);
extern void zigmaps_free(struct MapLayer *const map);
extern float *zigmaps_at(struct MapLayer *const map, float const x,
                         float const y);
extern struct MapLayer const *
zigmaps_make_traverse(struct MapLayer const *const map);

#endif
