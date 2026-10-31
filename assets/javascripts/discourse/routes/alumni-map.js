import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class extends DiscourseRoute {
  model(_params, transition) {
    // During a sidebar transition, window.location still belongs to the previous app.
    const query = new URLSearchParams({ ...transition.to.queryParams, lazy_cards: "1" }).toString();
    return ajax("/alumni-map/state.json" + (query ? "?" + query : ""));
  }
}
