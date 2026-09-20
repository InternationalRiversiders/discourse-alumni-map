import { apiInitializer } from "discourse/lib/api";
import CampusLifeSidebar from "../components/campus-life-sidebar";
export default apiInitializer((api) => {
  if (!api.container.lookup("service:site-settings").alumni_map_enabled) { return; }
  api.renderInOutlet("before-sidebar-sections", CampusLifeSidebar);
});
