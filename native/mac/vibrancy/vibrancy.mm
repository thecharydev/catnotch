// Glass on macOS: one NSVisualEffectView under the web contents, cut to the
// union of the notch's surfaces (spec 0013). Loaded by main/mac/vibrancy.ts.
//   attach(handle) / update(handle, shapes) / detach(handle)
// `handle` is the Buffer from BrowserWindow.getNativeWindowHandle(): an NSView*.
// Shape = { x, y, width, height, radii: [tl, tr, br, bl], ear?: 'left' | 'right' }
// in CSS pixels from the window's top left.
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <node_api.h>

static const char *kTag = "DeskNotchGlass";
static const CGFloat kK = 0.5523;  // quarter circle as a cubic curve
static const CGFloat kEar = 8;

static NSView *ContentOf(napi_env env, napi_value buf) {
  void *data = nullptr;
  size_t len = 0;
  if (napi_get_buffer_info(env, buf, &data, &len) != napi_ok || len < sizeof(void *)) return nil;
  NSView *view = (__bridge NSView *)(*(void **)data);
  return [view isKindOfClass:[NSView class]] ? view : nil;
}

static NSVisualEffectView *GlassIn(NSView *content) {
  for (NSView *v in content.subviews)
    if ([v.identifier isEqualToString:@(kTag)]) return (NSVisualEffectView *)v;
  return nil;
}

static double Num(napi_env env, napi_value obj, const char *key) {
  napi_value v;
  double d = 0;
  if (napi_get_named_property(env, obj, key, &v) == napi_ok) napi_get_value_double(env, v, &d);
  return d;
}

// One rounded rectangle with its own four radii, in y-down coordinates.
static void AddRounded(CGMutablePathRef p, CGRect r, const double rad[4]) {
  CGFloat x = r.origin.x, y = r.origin.y, w = r.size.width, h = r.size.height;
  CGFloat tl = rad[0], tr = rad[1], br = rad[2], bl = rad[3];
  CGPathMoveToPoint(p, NULL, x + tl, y);
  CGPathAddLineToPoint(p, NULL, x + w - tr, y);
  CGPathAddArcToPoint(p, NULL, x + w, y, x + w, y + tr, tr);
  CGPathAddLineToPoint(p, NULL, x + w, y + h - br);
  CGPathAddArcToPoint(p, NULL, x + w, y + h, x + w - br, y + h, br);
  CGPathAddLineToPoint(p, NULL, x + bl, y + h);
  CGPathAddArcToPoint(p, NULL, x, y + h, x, y + h - bl, bl);
  CGPathAddLineToPoint(p, NULL, x, y + tl);
  CGPathAddArcToPoint(p, NULL, x, y, x + tl, y, tl);
  CGPathCloseSubpath(p);
}

// The ear's box minus a disk at the corner away from the notch, as in the DOM
// mask. Pushed 0.5 into the notch so the two never leave a hairline seam.
static void AddEar(CGMutablePathRef p, CGRect r, bool left) {
  CGFloat x = r.origin.x, y = r.origin.y, e = kEar, k = kK * e;
  if (left) {
    CGPathMoveToPoint(p, NULL, x + e + 0.5, y + e);
    CGPathAddLineToPoint(p, NULL, x + e + 0.5, y);
    CGPathAddLineToPoint(p, NULL, x, y);
    CGPathAddCurveToPoint(p, NULL, x + k, y, x + e, y + e - k, x + e, y + e);
  } else {
    CGPathMoveToPoint(p, NULL, x - 0.5, y + e);
    CGPathAddLineToPoint(p, NULL, x - 0.5, y);
    CGPathAddLineToPoint(p, NULL, x + e, y);
    CGPathAddCurveToPoint(p, NULL, x + e - k, y, x, y + e - k, x, y + e);
  }
  CGPathCloseSubpath(p);
}

static napi_value Attach(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);
  NSView *content = argc ? ContentOf(env, args[0]) : nil;
  if (content && !GlassIn(content)) {
    NSVisualEffectView *fx = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    fx.identifier = @(kTag);
    fx.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    fx.state = NSVisualEffectStateActive;
    fx.material = NSVisualEffectMaterialHUDWindow;
    fx.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    fx.wantsLayer = YES;
    fx.hidden = YES;
    fx.autoresizingMask = NSViewNotSizable;
    [content addSubview:fx positioned:NSWindowBelow relativeTo:nil];
  }
  return NULL;
}

static napi_value Detach(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);
  NSView *content = argc ? ContentOf(env, args[0]) : nil;
  if (content) [GlassIn(content) removeFromSuperview];
  return NULL;
}

static napi_value Update(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);
  NSView *content = argc >= 2 ? ContentOf(env, args[0]) : nil;
  NSVisualEffectView *fx = content ? GlassIn(content) : nil;
  if (!fx) return NULL;

  uint32_t count = 0;
  napi_get_array_length(env, args[1], &count);
  CGMutablePathRef path = CGPathCreateMutable();
  CGRect bounds = CGRectNull;
  for (uint32_t i = 0; i < count; i++) {
    napi_value s, v;
    napi_get_element(env, args[1], i, &s);
    CGRect r = CGRectMake(Num(env, s, "x"), Num(env, s, "y"), Num(env, s, "width"), Num(env, s, "height"));
    if (r.size.width <= 0 || r.size.height <= 0) continue;
    double rad[4] = {0, 0, 0, 0};
    if (napi_get_named_property(env, s, "radii", &v) == napi_ok) {
      for (uint32_t j = 0; j < 4; j++) {
        napi_value n;
        if (napi_get_element(env, v, j, &n) == napi_ok) napi_get_value_double(env, n, &rad[j]);
      }
    }
    // The CSS rule: radii that overflow a side shrink together.
    double f = 1;
    f = MIN(f, r.size.width / MAX(rad[0] + rad[1], 1e-6));
    f = MIN(f, r.size.width / MAX(rad[3] + rad[2], 1e-6));
    f = MIN(f, r.size.height / MAX(rad[0] + rad[3], 1e-6));
    f = MIN(f, r.size.height / MAX(rad[1] + rad[2], 1e-6));
    for (int j = 0; j < 4; j++) rad[j] *= f;

    char ear[8] = {0};
    size_t n = 0;
    if (napi_get_named_property(env, s, "ear", &v) == napi_ok) napi_get_value_string_utf8(env, v, ear, sizeof ear, &n);
    if (n > 0) AddEar(path, r, ear[0] == 'l');
    else AddRounded(path, r, rad);
    bounds = CGRectUnion(bounds, CGRectInset(r, -1, 0));
  }

  if (CGRectIsNull(bounds)) {
    CGPathRelease(path);
    fx.hidden = YES;
    return NULL;
  }

  // The view is the bounding box; the mask is the path inside it, flipped from
  // CSS (y down) to AppKit (y up).
  CGFloat H = content.bounds.size.height;
  fx.frame = NSMakeRect(bounds.origin.x, H - CGRectGetMaxY(bounds), bounds.size.width, bounds.size.height);
  CGAffineTransform t = CGAffineTransformMake(1, 0, 0, -1, -bounds.origin.x, bounds.size.height);
  CGPathRef flipped = CGPathCreateCopyByTransformingPath(path, &t);
  CAShapeLayer *mask = [CAShapeLayer layer];
  mask.path = flipped;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  fx.layer.mask = mask;
  fx.hidden = NO;
  [CATransaction commit];
  CGPathRelease(flipped);
  CGPathRelease(path);
  return NULL;
}

static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor props[] = {
      {"attach", 0, Attach, 0, 0, 0, napi_default, 0},
      {"update", 0, Update, 0, 0, 0, napi_default, 0},
      {"detach", 0, Detach, 0, 0, 0, napi_default, 0},
  };
  napi_define_properties(env, exports, 3, props);
  return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
