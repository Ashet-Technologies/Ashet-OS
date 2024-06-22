#include "raycasterscene.hpp"
#include "src/display.hpp"
#include "src/fixed"
#include "src/systick.hpp"
#include "texture.hpp"

#include <array>
#include <cmath>
#include <limits>
#include <optional>

extern const PalettedTexture<32, 32> iron_walls;
extern const PalettedTexture<32, 32> dirt;
extern const PalettedTexture<32, 32> ceiling_tex;
extern const PalettedTexture<32, 32> indoor_wall;
extern const PalettedTexture<32, 32> indoor_door;
extern const PalettedTexture<32, 32> indoor_ceiling;
extern const PalettedTexture<32, 32> outdoor_door;
extern const PalettedTexture<320, 240> road_screenshot;

static const std::array<PalettedTexture<32, 32> const *, 4> wall_textures = {
    &iron_walls,
    &indoor_wall,
    &indoor_door,
    &outdoor_door,
};

namespace walls {
#include "raycast/scene.hpp"
}

struct WallGroup {
  Wall const *begin;
  Wall const *end;
};

std::array static const wall_groups = {
    WallGroup{walls::fixed_walls.begin(), walls::fixed_walls.end()},
    WallGroup{walls::doors.begin(), walls::doors.end()},
};

static char renderer_data[sizeof(Renderer)];

#define renderer reinterpret_cast<Renderer &>(renderer_data[0])

static size_t camera_index;
static uint32_t start_timer;
static real camrotaccell;

void RaycasterScene::init() { new (renderer_data) Renderer(); }

void RaycasterScene::start() {
  renderer.CameraPosition = walls::camera_path.front();
  renderer.CameraRotation = real(-1.571);
  camera_index = 0;
  start_timer = SysTick::time() + 200; // delay start of moving a bit
  camrotaccell = 0;
}

bool RaycasterScene::render() {
  if (SysTick::limit_framerate(100))
    return true;

  Display::set_entry_mode(Display::column_major, Display::increment,
                          Display::increment);
  Display::force_move(0, 0);
  Display::begin_put();
  renderer.drawWalls();

  if (start_timer > SysTick::time())
    return true;

  static_assert(walls::camera_path.size() > 0);
  if (camera_index >= walls::camera_path.size() - 1)
    return false; // we're actually done!

  {
    auto const curr = walls::camera_path[camera_index + 0];
    auto const next = walls::camera_path[camera_index + 1];

    real constexpr speed = 0.1;

    auto delta = (next - curr);
    delta *= speed / length(delta);

    real dist;
    if ((dist = distance2(renderer.CameraPosition, next)) < real(0.08)) {
      camera_index += 1;
    }

    renderer.CameraPosition += delta;

    auto const new_rot = real(std::atan2(double(delta.y), double(delta.x)));
    auto const old_rot = renderer.CameraRotation;

    if (new_rot == old_rot)
      camrotaccell = real(0);
    else
      camrotaccell = min(camrotaccell + real(0.01),
                         min(real(0.2), real(0.15) * abs(new_rot - old_rot)));

    auto const max_rot_spd = camrotaccell;
    auto delta_rot = new_rot - old_rot;
    if (abs(delta_rot) > max_rot_spd)
      delta_rot = copy_sign(max_rot_spd, delta_rot);

    renderer.CameraRotation +=
        delta_rot; // (real(9.0) * old_rot + new_rot) / 10.0;
  }

  // "open all doors" hack
  for (auto const &group : walls::door_groups) {
    auto const dist = distance2(group.center, renderer.CameraPosition);
    if (dist > real(5.0))
      continue;

    real constexpr speed = 0.1;

    auto const move = [&](Wall *wall) {
      auto d = wall->P1 - group.center;
      d *= speed / length(d);

      wall->P0 += d;
      wall->P1 += d;
    };
    if (group.left)
      move(group.left);
    if (group.right)
      move(group.right);
  }

  // renderer.CameraRotation += 0.1;

  return true;
}
