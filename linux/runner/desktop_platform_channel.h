#ifndef RUNNER_DESKTOP_PLATFORM_CHANNEL_H_
#define RUNNER_DESKTOP_PLATFORM_CHANNEL_H_

#include <gtk/gtk.h>

#include <flutter_linux/flutter_linux.h>

typedef struct _MyApplication MyApplication;

G_BEGIN_DECLS

typedef struct _DesktopPlatformChannel DesktopPlatformChannel;

DesktopPlatformChannel* desktop_platform_channel_new(
    MyApplication* application,
    GtkWindow* window,
    FlView* view);

void desktop_platform_channel_free(DesktopPlatformChannel* channel);

G_END_DECLS

#endif  // RUNNER_DESKTOP_PLATFORM_CHANNEL_H_
