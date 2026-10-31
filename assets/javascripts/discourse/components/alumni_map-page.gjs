import cardMasonry from "../modifiers/card-masonry";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "discourse/truth-helpers";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import AppForm from "./alumni_map-form";
import AppCard from "./alumni_map-card";
import AppIcon from "./alumni_map-icon";

import MapCanvas from "./alumni-map-canvas";
export default class extends Component {
  @tracked snapshot;
  @tracked regionCards = [];
  @tracked regionPagination;
  @tracked loadingCards = false;
  regionGeneration = 0;
  @tracked selectedRegion;
  @tracked busy = false;
  @tracked error = "";
  @tracked notice = "";
  get data() {
    return this.snapshot || this.args.model;
  }
  get query() {
    return new URLSearchParams(window.location.search);
  }
  @action async navigate(query, event) {
    if (
      event &&
      (event.metaKey ||
        event.ctrlKey ||
        event.shiftKey ||
        event.altKey ||
        event.button > 0)
    ) {
      return;
    }
    event?.preventDefault();
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = "";
    this.notice = "";
    try {
      const search = new URLSearchParams({ ...query, lazy_cards: "1" }).toString();
      this.clearRegion();
      const snapshot = await ajax("/alumni-map/state.json?" + search);
      if (this.isDestroying || this.isDestroyed) { return; }
      this.snapshot = snapshot;
      this.selectedRegion = null;
      window.history.replaceState({}, "", "/alumni-map?" + search);
      window.scrollTo({ top: 0, behavior: "auto" });
    } catch (e) {
      if (!this.isDestroying && !this.isDestroyed) { this.error = extractError(e); }
    } finally {
      if (!this.isDestroying && !this.isDestroyed) { this.busy = false; }
    }
  }
  @action tab(id, e) {
    return this.navigate({ view: id }, e);
  }
  @action async search(e) {
    e.preventDefault();
    const query = Object.fromEntries(new FormData(e.target));
    query.view = this.data.view;
    return this.navigate(query);
  }
  @action async execute(op, data, requestId) {
    this.error = "";
    this.notice = "";
    const result = await ajax("/alumni-map/action", {
      type: "POST",
      contentType: "application/json",
      data: JSON.stringify({ operation: op, data, request_id: requestId }),
    });
    if (this.isDestroying || this.isDestroyed) { return result; }
    this.notice = result.message || "已保存";
    try {
      const query = new URLSearchParams(result.query || Object.fromEntries(this.query));
      query.set("lazy_cards", "1");
      const snapshot = await ajax("/alumni-map/state.json?" + query);
      if (!this.isDestroying && !this.isDestroyed) {
        this.snapshot = snapshot;
        this.clearRegion();
        window.history.replaceState({}, "", "/alumni-map?" + query);
      }
    } catch {
      if (!this.isDestroying && !this.isDestroyed) { this.notice += "。页面暂未更新，请刷新查看，无需重复提交。"; }
    }
    return result;
  }
  @action async button(item) {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await this.execute(item.operation, item.data, crypto.randomUUID());
    } catch (e) {
      if (!this.isDestroying && !this.isDestroyed) { this.error = extractError(e); }
    } finally {
      if (!this.isDestroying && !this.isDestroyed) { this.busy = false; }
    }
  }
  get isDetail() {
    return [
      "post",
      "review",
      "shop",
      "course",
      "mentor",
      "teacher",
      "about",
    ].includes(this.data.view);
  }
  @action async selectRegion(region) {
    this.selectedRegion = region;
    await this.loadRegion(1);
  }
  @action clearRegion() {
    this.regionGeneration++;
    this.selectedRegion = null;
    this.regionCards = [];
    this.regionPagination = null;
    this.loadingCards = false;
  }
  @action async loadRegion(page) {
    const region = this.selectedRegion;
    if (!region || !this.data.map?.lazy_cards) { return; }
    const generation = ++this.regionGeneration;
    this.loadingCards = true;
    this.regionCards = [];
    this.regionPagination = null;
    this.error = "";
    try {
      const query = new URLSearchParams({ cards_only: "1", region_key: region.key, page, q: this.query.get("q") || "" });
      const result = await ajax("/alumni-map/state.json?" + query);
      if (this.isDestroying || this.isDestroyed || generation !== this.regionGeneration) { return; }
      this.regionCards = result.cards;
      this.regionPagination = result.pagination;
    } catch (error) {
      if (!this.isDestroying && !this.isDestroyed && generation === this.regionGeneration) { this.error = extractError(error); }
    } finally {
      if (!this.isDestroying && !this.isDestroyed && generation === this.regionGeneration) { this.loadingCards = false; }
    }
  }
  get visibleCards() {
    if (!this.data.map) { return this.data.cards || []; }
    if (this.data.map.lazy_cards) { return this.regionCards; }
    const ids = new Set((this.selectedRegion?.ids || []).map(String));
    return (this.data.cards || []).filter((card) => ids.has(String(card.id)));
  }
  get regionChoices() {
    return this.data.map?.regions?.province || [];
  }
  get hasCards() {
    return Boolean(this.visibleCards.length);
  }
  get hasForms() {
    return Boolean(this.data.forms?.length);
  }
  get showEmpty() {
    return !this.hasForms && (this.data.map ? this.data.map.profile_count === 0 : !this.hasCards);
  }
  get workspaceClass() {
    return `river-workspace ${this.isDetail ? "is-detail" : ""} ${this.hasForms ? "has-forms" : ""} ${!this.hasCards && this.hasForms ? "form-only" : ""}`;
  }
  get currentTitle() {
    return (
      this.data.tabs.find((tab) => tab.id === this.data.view)?.label ||
      {
        post: "树洞里的对话",
        review: "评价与讨论",
        shop: "店铺详情",
        course: "课程详情",
        mentor: "导师详情",
        teacher: "任课教师",
      }[this.data.view] ||
      "内容详情"
    );
  }
  get primaryFilter() {
    return this.data.filters[0];
  }
  get extraFilters() {
    return this.data.filters.slice(1);
  }
  get activeFilters() {
    return this.extraFilters.some((field) => Boolean(field.value));
  }
  <template>
    <main
      class="river-app river-alumni_map"
      data-view={{this.data.view}}
      aria-busy={{this.busy}}
    >
      <h1 class="sr-only">{{this.data.title}}</h1>
      <nav class="river-tabs" aria-label="功能导航">{{#each
          this.data.tabs key="id"
          as |tab|
        }}<button
            type="button"
            class={{if (eq tab.id this.data.view) "is-active"}}
            aria-current={{if (eq tab.id this.data.view) "page"}}
            disabled={{this.busy}}
            {{on "click" (fn this.tab tab.id)}}
          >{{tab.label}}</button>{{/each}}</nav>
      {{#if this.error}}<div
          class="river-error"
          role="alert"
        >{{this.error}}</div>{{/if}}
      {{#if this.notice}}<div class="river-notice" role="status"><AppIcon
            @kind="check"
          />{{this.notice}}</div>{{/if}}

      {{#if this.data.stats}}<div class="river-stats">{{#each
            this.data.stats
            as |stat|
          }}<div><span>{{stat.label}}</span><strong
              >{{stat.value}}</strong></div>{{/each}}</div>{{/if}}
      {{#if this.data.filters}}<form
          class="river-search"
          role="search"
          {{on "submit" this.search}}
        >
          <div class="river-search-main"><span
              class="river-search-mark"
            ><AppIcon @kind="search" /></span><label
            >{{this.primaryFilter.label}}<input
                type="search"
                name={{this.primaryFilter.name}}
                value={{this.primaryFilter.value}}
                placeholder={{this.primaryFilter.placeholder}}
              /></label><button
              class="btn btn-primary"
              type="submit"
              disabled={{this.busy}}
            >筛选<AppIcon @kind="arrow" /></button></div>
          {{#if this.extraFilters.length}}<details
              class="river-filter-extra"
              open={{this.activeFilters}}
            ><summary>更多筛选</summary><div class="river-filter-fields">{{#each
                  this.extraFilters
                  as |field|
                }}<label>{{field.label}}<input
                      type="text"
                      name={{field.name}}
                      value={{field.value}}
                      placeholder={{field.placeholder}}
                    /></label>{{/each}}</div></details>{{/if}}
        </form>{{/if}}
      {{#if this.data.map}}
        <MapCanvas @data={{this.data.map}} @selectedRegion={{this.selectedRegion}} @selectRegion={{this.selectRegion}} @clearRegion={{this.clearRegion}} />
        <div class="alumni-map-guide"><AppIcon @kind="map" /><span>点击光圈查看该区域的校友，放大地图可查看各个城市。</span></div>
        <details class="alumni-region-picker"><summary>按地区选择 <span>{{this.regionChoices.length}} 个地区</span></summary>
          <div class="alumni-region-options">{{#each this.regionChoices key="key" as |region|}}
            <button type="button" class={{if (eq this.selectedRegion.key region.key) "is-active"}} aria-pressed={{eq this.selectedRegion.key region.key}} {{on "click" (fn this.selectRegion region)}}>{{region.label}}<span>{{region.count}}</span></button>
          {{/each}}</div>
        </details>
      {{/if}}
      {{#if (eq this.data.view "me")}}<p><a href="/alumni-map/export" download>下载我的名片数据</a></p>{{/if}}
      {{#if this.data.note}}<p class="river-note"><AppIcon @kind="map" /><span
          >{{this.data.note}}</span></p>{{/if}}

      {{#if this.data.pagination}}<nav class="alumni-pagination" aria-label="名片分页">
        {{#if this.data.pagination.previous}}<button type="button" class="btn" disabled={{this.busy}} {{on "click" (fn this.navigate this.data.pagination.previous)}}>上一页</button>{{/if}}
        <span>第 {{this.data.pagination.page}} / {{this.data.pagination.pages}} 页</span>
        {{#if this.data.pagination.next}}<button type="button" class="btn" disabled={{this.busy}} {{on "click" (fn this.navigate this.data.pagination.next)}}>下一页</button>{{/if}}
      </nav>{{/if}}
      {{#if this.loadingCards}}<p role="status" class="river-note">正在加载校友名片…</p>{{/if}}
      {{#if this.regionPagination}}<nav class="alumni-pagination" aria-label="地区名片分页">
        {{#if this.regionPagination.previous}}<button type="button" class="btn" disabled={{this.loadingCards}} {{on "click" (fn this.loadRegion this.regionPagination.previous)}}>上一页</button>{{/if}}
        <span>第 {{this.regionPagination.page}} / {{this.regionPagination.pages}} 页 · {{this.regionPagination.total}} 位校友</span>
        {{#if this.regionPagination.next}}<button type="button" class="btn" disabled={{this.loadingCards}} {{on "click" (fn this.loadRegion this.regionPagination.next)}}>下一页</button>{{/if}}
      </nav>{{/if}}
      <div class={{this.workspaceClass}}>
        {{#if this.hasCards}}<section
            class="river-content"
            aria-label={{this.currentTitle}}
          ><div class="river-section-heading"><h2
              >{{if this.data.map this.selectedRegion.label this.currentTitle}}</h2><span>{{#if this.data.map}}{{this.visibleCards.length}} 位校友{{else}}在不同的城市，延续同一份连接{{/if}}</span>
              {{#if this.data.map}}<button type="button" class="btn btn-flat" {{on "click" this.clearRegion}}>关闭名片</button>{{/if}}</div>
            <div class="river-grid" {{cardMasonry ".river-card"}}>{{#each
                this.visibleCards key="id"
                as |card|
              }}<AppCard
                  @card={{card}}
                  @busy={{this.busy}}
                  @navigate={{this.navigate}}
                  @button={{this.button}}
                  @execute={{this.execute}}
                />{{/each}}</div>
          </section>{{/if}}
        {{#if this.hasForms}}<section
            class="river-forms"
            aria-label="填写与操作"
          >{{#each this.data.forms as |form|}}<AppForm
                @form={{form}}
                @execute={{this.execute}}
              />{{/each}}</section>{{/if}}
        {{#if this.showEmpty}}<div class="river-empty"><span
              class="river-empty-icon"
            ><AppIcon @kind="map" /></span><strong
            >{{this.data.empty_title}}</strong><p
            >{{this.data.empty_text}}</p></div>{{/if}}
      </div>
      {{#if this.data.next}}<div class="river-pagination"><button
            class="btn"
            type="button"
            disabled={{this.busy}}
            {{on "click" (fn this.navigate this.data.next)}}
          >下一页<AppIcon @kind="arrow" /></button></div>{{/if}}
    </main>
  </template>
}
