import os

application = defines["app"]
appname = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}

default_view = "icon-view"
# Icon locations are icon centres in window coordinates; both icons sit
# symmetrically around the horizontal centre of the 480 px wide window.
window_rect = ((100, 100), (480, 280))
icon_size = 96
text_size = 13
icon_locations = {
    appname: (140, 120),
    "Applications": (340, 120),
}
