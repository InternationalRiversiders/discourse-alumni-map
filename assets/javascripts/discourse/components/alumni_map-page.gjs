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
      const search = new URLSearchParams(query).toString();
      this.snapshot = await ajax("/alumni-map/state.json?" + search);
      this.selectedRegion = null;
      window.history.replaceState({}, "", "/alumni-map?" + search);
      window.scrollTo({ top: 0, behavior: "auto" });
    } catch (e) {
      this.error = extractError(e);
    } finally {
      this.busy = false;
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
    this.snapshot = await ajax(
      "/alumni-map/state.json?" + this.query.toString()
    );
    this.notice = result.message || "已保存";
    if (result.query) {
      await this.navigate(result.query);
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
      this.error = extractError(e);
    } finally {
      this.busy = false;
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
  @action selectRegion(region) {
    this.selectedRegion = region;
  }
  @action clearRegion() {
    this.selectedRegion = null;
  }
  get visibleCards() {
    if (!this.data.map) {
      return this.data.cards || [];
    }
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
    return !this.hasForms && (this.data.map ? !this.data.cards?.length : !this.hasCards);
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
  get showAction() {
    return (
      this.data.member && this.data.view !== "me" && this.data.view !== "admin"
    );
  }
  @action primaryAction(event) {
    return this.navigate({ view: "me" }, event);
  }
  <template>
    <main
      class="river-app river-alumni_map"
      data-view={{this.data.view}}
      aria-busy={{this.busy}}
    >
      <header class="river-hero">
        <div class="river-hero-copy"><span class="river-eyebrow"><span
              class="river-brand-dot"
            ></span>RIVERSIDE / ALUMNI</span><h1>{{this.data.title}}</h1><p
          >{{this.data.intro}}</p>
          {{#if this.showAction}}<button
              class="river-hero-action"
              type="button"
              disabled={{this.busy}}
              {{on "click" this.primaryAction}}
            >我的名片<AppIcon @kind="arrow" /></button>{{/if}}
        </div>
        <div class="river-hero-art" aria-hidden="true"><span
            class="river-orbit"
          ></span><span class="river-art-tile"><AppIcon
              @kind="map"
            /></span><span class="river-art-dot"></span></div>
      </header>
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
      <div class={{this.workspaceClass}}>
        {{#if this.hasCards}}<section
            class="river-content"
            aria-label={{this.currentTitle}}
          ><div class="river-section-heading"><h2
              >{{if this.data.map this.selectedRegion.label this.currentTitle}}</h2><span>{{#if this.data.map}}{{this.visibleCards.length}} 位校友{{else}}在不同的城市，延续同一份连接{{/if}}</span>
              {{#if this.data.map}}<button type="button" class="btn btn-flat" {{on "click" this.clearRegion}}>关闭名片</button>{{/if}}</div>
            <div class="river-grid">{{#each
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
