import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import AppForm from "./alumni_map-form";
import AppIcon from "./alumni_map-icon";
const href = (query) => "/alumni-map?" + new URLSearchParams(query).toString();
export default class extends Component {
  get initial() {
    return Array.from(this.args.card.title || "")
      .slice(0, 1)
      .join("");
  }
  <template>
    <article class="river-card" data-card-id={{@card.id}} id="alumni-profile-{{@card.id}}" tabindex="-1">
      <div class="river-card-heading">
        <span
          class="river-card-symbol"
          aria-hidden="true"
        >{{this.initial}}</span>
        <div class="river-card-heading-text">{{#if @card.tag}}<span
              class="river-tag"
            >{{@card.tag}}</span>{{/if}}
          <h2>{{@card.title}}</h2>{{#if @card.subtitle}}<p
              class="river-meta"
            >{{#if @card.profile_url}}<a href={{@card.profile_url}} data-user-card={{@card.subtitle}}>@{{@card.subtitle}}</a>{{else}}{{@card.subtitle}}{{/if}}</p>{{/if}}
        </div>
      </div>
      {{#if @card.images}}<div class="river-images">{{#each
            @card.images
            as |url|
          }}<a href={{url}} target="_blank" rel="noopener"><img
                src={{url}}
                alt={{@card.title}}
                loading="lazy"
              /></a>{{/each}}</div>{{/if}}
      {{#if @card.body}}<p class="river-body">{{@card.body}}</p>{{/if}}
      {{#if @card.profile_fields}}<dl class="alumni-profile-fields">
          {{#each @card.profile_fields as |field|}}<div><dt>{{field.label}}</dt><dd>{{field.value}}</dd></div>{{/each}}
        </dl>{{/if}}
      {{#if @card.metrics}}<dl class="river-metrics">{{#each
            @card.metrics
            as |metric|
          }}<div><dt>{{metric.label}}</dt><dd
              >{{metric.value}}</dd></div>{{/each}}</dl>{{/if}}
      {{#if @card.links.length}}<div class="river-card-links">{{#each
            @card.links
            as |link|
          }}<a
              href={{href link.query}}
              {{on "click" (fn @navigate link.query)}}
            >{{link.label}}<AppIcon @kind="arrow" /></a>{{/each}}</div>{{/if}}
      {{#if @card.actions.length}}<div class="river-actions">{{#each
            @card.actions
            as |item|
          }}<button
              class="btn btn-default btn-small"
              type="button"
              disabled={{@busy}}
              {{on "click" (fn @button item)}}
            >{{item.label}}</button>{{/each}}</div>{{/if}}
      {{#each @card.forms as |form|}}<details
          class="river-discussion-form"
        ><summary>{{if form.title form.title "回复"}}</summary><AppForm
            @form={{form}}
            @execute={{@execute}}
          /></details>{{/each}}
    </article>
  </template>
}
