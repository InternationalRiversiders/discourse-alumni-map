import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";
export default class extends DiscourseRoute {
  model() { return ajax("/alumni-map/state.json" + window.location.search); }
}
