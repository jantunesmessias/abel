import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_lucide/generated_icons/camera.dart' as lucide_camera;
import 'package:jaspr_lucide/generated_icons/circle_check.dart'
    as lucide_circle_check;
import 'package:jaspr_lucide/generated_icons/clipboard_check.dart'
    as lucide_clipboard_check;
import 'package:jaspr_lucide/generated_icons/cloud_cog.dart'
    as lucide_cloud_cog;
import 'package:jaspr_lucide/generated_icons/layout_dashboard.dart'
    as lucide_dashboard;
import 'package:jaspr_lucide/generated_icons/list.dart' as lucide_list;
import 'package:jaspr_lucide/generated_icons/map.dart' as lucide_map;
import 'package:jaspr_lucide/generated_icons/maximize2.dart' as lucide_maximize;
import 'package:jaspr_lucide/generated_icons/monitor_play.dart'
    as lucide_monitor_play;
import 'package:jaspr_lucide/generated_icons/play.dart' as lucide_play;
import 'package:jaspr_lucide/generated_icons/radio_tower.dart'
    as lucide_radio_tower;
import 'package:jaspr_lucide/generated_icons/refresh_cw.dart' as lucide_refresh;
import 'package:jaspr_lucide/generated_icons/route.dart' as lucide_route;
import 'package:jaspr_lucide/generated_icons/search.dart' as lucide_search;
import 'package:jaspr_lucide/generated_icons/sliders_horizontal.dart'
    as lucide_filters;
import 'package:jaspr_lucide/generated_icons/square.dart' as lucide_square;
import 'package:jaspr_lucide/generated_icons/triangle_alert.dart'
    as lucide_alert;
import 'package:jaspr_lucide/generated_icons/unplug.dart' as lucide_unplug;
import 'package:jaspr_lucide/generated_icons/waypoints.dart'
    as lucide_waypoints;
import 'package:jaspr_lucide/generated_icons/x.dart' as lucide_x;
import 'package:jaspr_lucide/generated_icons/zoom_in.dart' as lucide_zoom_in;
import 'package:jaspr_lucide/generated_icons/zoom_out.dart' as lucide_zoom_out;

enum DevExIconName {
  overview,
  journey,
  target,
  gateway,
  review,
  remote,
  hosted,
  map,
  list,
  refresh,
  search,
  filters,
  zoomIn,
  zoomOut,
  fit,
  capture,
  play,
  stop,
  success,
  warning,
  disconnected,
  close,
}

/// Tree-shakeable, presentation-owned Lucide icon.
final class DevExIcon extends StatelessComponent {
  const DevExIcon({required this.name, this.size = 18, super.key});

  final DevExIconName name;
  final double size;

  @override
  Component build(BuildContext context) {
    final dimension = Unit.pixels(size);
    const attributes = <String, String>{
      'aria-hidden': 'true',
      'focusable': 'false',
    };
    return switch (name) {
      DevExIconName.overview => lucide_dashboard.LayoutDashboard(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.journey => lucide_route.Route(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.target => lucide_monitor_play.MonitorPlay(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.gateway => lucide_waypoints.Waypoints(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.review => lucide_clipboard_check.ClipboardCheck(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.remote => lucide_radio_tower.RadioTower(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.hosted => lucide_cloud_cog.CloudCog(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.map => lucide_map.Map(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.list => lucide_list.List(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.refresh => lucide_refresh.RefreshCw(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.search => lucide_search.Search(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.filters => lucide_filters.SlidersHorizontal(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.zoomIn => lucide_zoom_in.ZoomIn(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.zoomOut => lucide_zoom_out.ZoomOut(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.fit => lucide_maximize.Maximize2(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.capture => lucide_camera.Camera(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.play => lucide_play.Play(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.stop => lucide_square.Square(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.success => lucide_circle_check.CircleCheck(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.warning => lucide_alert.TriangleAlert(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.disconnected => lucide_unplug.Unplug(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
      DevExIconName.close => lucide_x.X(
        width: dimension,
        height: dimension,
        classes: 'dx-icon',
        attributes: attributes,
      ),
    };
  }
}
