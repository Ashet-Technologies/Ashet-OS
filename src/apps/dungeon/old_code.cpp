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

class Renderer {
private:
private:
  std::array<real, width> zbuffer;
  std::array<vec2_t, width> protorays;

public:
  vec2_t CameraPosition;
  real CameraRotation;

public:
  explicit Renderer() : protorays(), CameraPosition(0, 0), CameraRotation(0) {}

public:
  //    template<typename SpriteCollection>
  //    void sortSprites(SpriteCollection & sprites)
  //    {
  //        std::sort(std::begin(sprites), std::end(sprites),
  //        [this](Sprite<real> const & a, Sprite<real> const & b) {
  //            // "a < b"
  //            return distance2(a.position, this->CameraPosition) <
  //            distance2(b.position, this->CameraPosition);
  //        });
  //    }

  //    template<typename SpriteCollection>
  //    void drawSprites(SpriteCollection const & sprites)
  //    {
  //        // then draw the sprites
  //        for(auto const & sprite : sprites)
  //        {
  //            auto delta = sprite.position - this->CameraPosition;
  //            auto angle = Basic3D::angdiff(std::atan2(delta.y, delta.x),
  //            this->CameraRotation);

  //            if (std::abs(angle) > Basic3D::PiOver2)
  //                continue;

  //            auto distance2 = length2(delta);
  //            if (distance2 < 0.0025f) // 0.05²
  //                continue; // discard early

  //            auto distance = std::sqrt(distance2);

  //            // if(distance > 100)
  //            //  continue; // discard far objects

  //            auto fx = 2.0 * std::tan(angle) / aspect;

  //            auto cx = int((width - 1) * (0.5 + 0.5 * fx));

  //            auto texture = sprite.texture;

  //            // calculate perspective correction
  //            auto correction = std::sqrt(0.5f * fx * fx + 1);

  //            // calculate on-screen size
  //            auto spriteHeight = int(correction * height / distance);
  //            auto spriteWidth = (texture->width * spriteHeight) /
  //            texture->height;

  //            // discard the sprite when out of screen
  //            if ((cx + spriteWidth) < 0)
  //                continue;
  //            if ((cx - spriteWidth) >= width)
  //                continue;

  //            // calculate screen positions and boundaries
  //            auto wallTop = (height / 2) - (spriteHeight / 2);
  //            auto wallBottom = (height / 2) + (spriteHeight / 2);

  //            auto left = cx - spriteWidth / 2;

  //            auto minx = std::max(0, left);
  //            auto maxx = std::min(width - 1, cx + spriteWidth / 2);

  //            auto miny = std::max(0, wallTop);
  //            auto maxy = std::min(height, wallBottom);

  //            // render the sprite also column major
  //            for (int x = minx; x < maxx; x++)
  //            {
  //                // Test if we are occluded by a sprite
  //                if (zbuffer[x] < distance)
  //                    continue;

  //                auto u = (texture->width - 1) * (x - left) / (spriteWidth -
  //                1);

  //                for (int y = miny; y < maxy; y++)
  //                {
  //                    auto v = (texture->height - 1) * (y - wallTop) /
  //                    (spriteHeight - 1); pixel_t c = texture->sample(u, v);

  //                    // alpha testing
  //                    if ((c.alpha & 0x80) == 0)
  //                        continue;

  //                    setPixel(x,y,c);
  //                }
  //            }
  //        }
  //    }
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
