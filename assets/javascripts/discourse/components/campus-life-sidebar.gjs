import Component from "@glimmer/component";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { modifier } from "ember-modifier";
import SidebarSection from "discourse/components/sidebar/section";
import SidebarSectionLink from "discourse/components/sidebar/section-link";

export default class extends Component {
  @service currentUser;
  @service siteSettings;
  @service sidebarState;
  @tracked target;

  get links() {
    const u = this.currentUser;
    const s = this.siteSettings;
    const entries = [
      [s.food_enabled, "food", "觅电", "utensils", "food"],
      [s.whisper_enabled && u?.whisper_member, "whisper", "树洞", "leaf", "whisper"],
      [s.courses_enabled && u?.courses_member, "courses", "选课指南", "graduation-cap", "courses"],
      [s.alumni_map_enabled && u?.alumni_map_member, "alumni-map", "校友地图", "map-location-dot", "alumni-map"],
      [s.rsdate_enabled && u?.rsdate_member, "rsdate", "RS Date", "heart", "rsdate"],
    ];
    return entries.filter(([visible]) => visible).map(([,name,text,icon,route]) => ({name,text,icon,route}));
  }
  get visible() { return this.sidebarState.showMainPanel && this.links.length > 0; }
  get title() { return this.siteSettings.alumni_map_sidebar_section_title || "校园生活"; }
  mount = modifier((element) => {
    // The public outlet precedes the whole sidebar. Own a separate portal slot
    // immediately before categories, without moving any Ember-owned core nodes.
    const root = element.closest("#d-sidebar, .sidebar-hamburger-dropdown");
    if (!root) { return; }
    const slot = document.createElement("div");
    slot.className = "campus-life-sidebar-slot";
    let disposed = false;
    const place = () => {
      if (disposed) { return; }
      const sections = root.querySelector(".sidebar-sections");
      if (!sections) { slot.remove(); return; }
      const categories = sections.querySelector(':scope > [data-section-name="categories"]');
      const custom = sections.querySelector(":scope > .sidebar-custom-sections");
      if (categories) {
        if (slot.parentElement !== sections || slot.nextSibling !== categories) {
          sections.insertBefore(slot, categories);
        }
      } else if (custom && custom.nextSibling !== slot) {
        custom.after(slot);
      }
    };
    const observer = new MutationObserver(place);
    observer.observe(root, {childList: true, subtree: true});
    queueMicrotask(() => { if (!disposed) { this.target = slot; place(); } });
    return () => { disposed = true; observer.disconnect(); slot.remove(); };
  });
  <template>
    <span hidden {{this.mount}}></span>
    {{#if this.target}}
      {{#in-element this.target}}
        {{#if this.visible}}
          <SidebarSection
            @sectionName="campus-life"
            @headerLinkText={{this.title}}
            @headerLinkTitle={{this.title}}
            @displaySection={{true}}
            @collapsable={{true}}
            @collapsedByDefault={{false}}
          >
            {{#each this.links key="name" as |entry|}}
              <SidebarSectionLink
                @linkName={{entry.name}}
                @content={{entry.text}}
                @title={{entry.text}}
                @route={{entry.route}}
                @prefixType="icon"
                @prefixValue={{entry.icon}}
              />
            {{/each}}
          </SidebarSection>
        {{/if}}
      {{/in-element}}
    {{/if}}
  </template>
}
