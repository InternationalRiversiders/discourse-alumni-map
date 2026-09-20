import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";

export default class extends Component {
  @service appEvents;
  frame;
  selection = modifier((_element, [region]) => {
    this.frame?.contentWindow?.postMessage({ type: "alumni-map-selection", key: region?.key || null }, "*");
  });
  @tracked error = "";
  @tracked loading = true;
  @action retry() {
    window.location.reload();
  }
  setup = modifier((element, [data]) => {
    this.error = "";
    this.loading = true;
    delete element.dataset.mapLoaded;
    const frame = document.createElement("iframe");
    frame.title = "校友城市地图";
    frame.setAttribute("sandbox", "allow-scripts");
    frame.src = "/alumni-map/map-frame";
    frame.style.cssText = "width:100%;height:100%;border:0;display:block";
    this.frame = frame;
    // Read Discourse's active palette, including forced modes and OS auto mode.
    // Listening only to prefers-color-scheme would ignore the user's forum choice.
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const theme = () => getComputedStyle(document.body).getPropertyValue("--scheme-type").trim() === "dark" ? "dark" : "light";
    let themeFrame;
    const updateTheme = () => {
      cancelAnimationFrame(themeFrame);
      themeFrame = requestAnimationFrame(() => frame.contentWindow?.postMessage({ type: "alumni-map-theme", theme: theme() }, "*"));
    };
    this.appEvents.on("interface-color:changed", updateTheme);
    media.addEventListener("change", updateTheme);
    document.addEventListener("load", updateTheme, true);
    const observer = new MutationObserver(updateTheme);
    observer.observe(document.head, { subtree: true, childList: true, attributes: true, attributeFilter: ["media", "href", "disabled"] });
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class", "style"] });
    observer.observe(document.body, { attributes: true, attributeFilter: ["class", "style"] });
    const regions = new Map(Object.values(data.regions).flat().map((region) => [region.key, region]));
    // The third-party map SDK only needs aggregate locations and counts.
    // Keep profile names, IDs and card details in the forum document.
    const sandboxData = {
      key: data.key,
      security: data.security,
      regions: Object.fromEntries(Object.entries(data.regions).map(([level, items]) => [
        level, items.map(({ key, label, count, lat, lng }) => ({ key, label, count, lat, lng })),
      ])),
    };
    const fail = () => {
      this.loading = false;
      this.error = "底图未能加载。可以重试，也可以通过下方的地区选择查看校友。";
    };
    const timeout = setTimeout(fail, 30000);
    const receive = (event) => {
      if (event.source !== frame.contentWindow || event.origin !== "null") {
        return;
      }
      if (event.data?.type === "alumni-map-loaded" && event.data.tiles >= 2) {
        clearTimeout(timeout);
        element.dataset.mapLoaded = "true";
        this.loading = false;
        this.error = "";
      } else if (event.data?.type === "alumni-map-error") {
        clearTimeout(timeout);
        fail();
      } else if (event.data?.type === "alumni-map-clear") {
        this.args.clearRegion();
      } else if (event.data?.type === "alumni-map-region") {
        const region = regions.get(event.data.key);
        if (region) {
          this.args.selectRegion(region);
        }
      }
    };
    window.addEventListener("message", receive);
    frame.onload = () => {
      // Opaque-origin sandbox windows require "*" as targetOrigin. The
      // destination is this specific frame; replies also verify its Window.
      frame.contentWindow.postMessage({ type: "alumni-map-init", data: sandboxData, theme: theme(), selected: this.args.selectedRegion?.key }, "*");
    };
    element.appendChild(frame);
    return () => {
      window.removeEventListener("message", receive);
      this.appEvents.off("interface-color:changed", updateTheme);
      media.removeEventListener("change", updateTheme);
      document.removeEventListener("load", updateTheme, true);
      observer.disconnect();
      cancelAnimationFrame(themeFrame);
      if (this.frame === frame) { this.frame = null; }
      clearTimeout(timeout);
      frame.remove();
    };
  });
  <template>
    {{#if @data.key}}<div class="river-map" {{this.setup @data}} {{this.selection @selectedRegion}}></div>{{else}}<p
        class="river-note"
      >地图服务尚未配置，可以通过地区选择查看校友。</p>{{/if}}
    {{#if this.loading}}{{#if @data.key}}<p role="status" class="river-note">正在加载底图…</p>{{/if}}{{/if}}
    {{#if this.error}}<div role="status" class="alumni-map-error"><span>{{this.error}}</span><button class="btn" type="button" {{on "click" this.retry}}>重新加载地图</button></div>{{/if}}
  </template>
}
