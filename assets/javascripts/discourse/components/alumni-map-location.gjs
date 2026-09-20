import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { modifier } from "ember-modifier";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";

export default class extends Component {
  @tracked country = "";
  @tracked province = "";
  @tracked city = "";
  @tracked latitude = "";
  @tracked longitude = "";
  @tracked countries = [];
  @tracked provinces = [];
  @tracked cities = [];
  @tracked loading = false;
  @tracked error = "";
  @tracked changed = false;
  generation = 0;
  get countryCode() { return this.countries.find(c => c.name === this.country)?.code; }
  get provinceCode() { return this.provinces.find(s => s.name === this.province)?.code; }
  // Retain imported spellings and cities missing from the legacy catalog.
  get countryOptions() { return this.withCurrent(this.countries, this.country); }
  get provinceOptions() { return this.withCurrent(this.provinces, this.province); }
  get cityOptions() { return this.withCurrent(this.cities, this.city); }
  withCurrent(options, name) { return name && !options.some(o => o.name === name) ? [{name}, ...options] : options; }
  setup = modifier((_element, [fields]) => {
    let cancelled = false;
    // Initialize after the current render. Synchronous tracked writes inside a
    // modifier can invalidate Glimmer's in-progress select/option rendering.
    queueMicrotask(() => {
      if (cancelled) { return; }
      for (const name of ["country", "province", "city", "latitude", "longitude"]) {
        this[name] = fields.find(f => f.name === name)?.value ?? "";
      }
      this.changed = false;
      this.load("countries");
    });
    return () => { cancelled = true; this.generation++; };
  });
  async load(level) {
    const generation = ++this.generation;
    this.loading = true;
    this.error = "";
    try {
      if (level === "countries") {
        const options = await ajax("/alumni-map/locations.json");
        if (generation !== this.generation) { return; }
        this.countries = options;
      }
      if (level !== "cities" && this.countryCode) {
        const options = await ajax("/alumni-map/locations.json", {data: {country: this.countryCode}});
        if (generation !== this.generation) { return; }
        this.provinces = options;
      }
      if (this.countryCode && this.provinceCode) {
        const options = await ajax("/alumni-map/locations.json", {data: {country: this.countryCode, province: this.provinceCode}});
        if (generation !== this.generation) { return; }
        this.cities = options;
      }
    } catch {
      if (generation === this.generation) { this.error = "地区列表暂时无法加载。原有位置仍保留，可以重试。"; }
    } finally {
      if (generation === this.generation) { this.loading = false; }
    }
  }
  resetCoordinates() { this.latitude = ""; this.longitude = ""; this.changed = true; }
  @action countryChanged(e) {
    this.country = e.target.value;
    this.province = ""; this.city = ""; this.provinces = []; this.cities = [];
    this.resetCoordinates(); this.load("provinces");
  }
  @action provinceChanged(e) {
    this.province = e.target.value; this.city = ""; this.cities = [];
    this.resetCoordinates(); this.load("cities");
  }
  @action cityChanged(e) {
    this.city = e.target.value;
    this.resetCoordinates();
    // Coordinates are resolved and rounded server-side from the same catalog.
  }
  @action retry() { this.load("countries"); }
  <template>
    <div class="alumni-location river-field-wide" {{this.setup @fields}}>
      <div class="river-fields">
        <label><span>国家 / 地区</span><select name="country" aria-label="国家 / 地区" disabled={{this.loading}} {{on "change" this.countryChanged}}>
          <option value="" selected={{eq this.country ""}}>不填写位置</option>
          {{#each this.countryOptions as |item|}}<option value={{item.name}} selected={{eq item.name this.country}}>{{item.name}}</option>{{/each}}
        </select></label>
        <label><span>省 / 州</span><select name="province" aria-label="省 / 州" disabled={{this.loading}} {{on "change" this.provinceChanged}}>
          <option value="" selected={{eq this.province ""}}>请选择（可选）</option>
          {{#each this.provinceOptions as |item|}}<option value={{item.name}} selected={{eq item.name this.province}}>{{item.name}}</option>{{/each}}
        </select></label>
        <label><span>城市</span><select name="city" aria-label="城市" disabled={{this.loading}} {{on "change" this.cityChanged}}>
          <option value="" selected={{eq this.city ""}}>请选择（可选）</option>
          {{#each this.cityOptions as |item|}}<option value={{item.name}} selected={{eq item.name this.city}}>{{item.name}}</option>{{/each}}
        </select></label>
      </div>
      <input type="hidden" name="latitude" value={{this.latitude}} />
      <input type="hidden" name="longitude" value={{this.longitude}} />
      <input type="hidden" name="location_changed" value={{this.changed}} />
      {{#if this.loading}}<p role="status" class="river-note">正在加载地区…</p>{{/if}}
      {{#if this.error}}<p role="status" class="river-error">{{this.error}} <button class="btn" type="button" {{on "click" this.retry}}>重试</button></p>{{/if}}
    </div>
  </template>
}
