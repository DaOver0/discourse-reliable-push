import Component from "@glimmer/component";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";

export default class ReliablePushPreferences extends Component {
  @service currentUser;
  @service siteSettings;
  @service("reliable-push") reliablePush;

  get show() {
    return (
      this.siteSettings.reliable_push_enabled &&
      this.currentUser &&
      this.args.outletArgs?.model?.id === this.currentUser.id
    );
  }

  <template>
    {{#if this.show}}
      <section class="reliable-push-status" aria-live="polite">
        <div class="reliable-push-status__title">{{i18n "discourse_reliable_push.title"}}</div>
        <p class="reliable-push-status__description">{{i18n "discourse_reliable_push.description"}}</p>
        <p class="reliable-push-status__message">{{i18n this.reliablePush.statusKey}}</p>
        <div class="reliable-push-status__actions">
          {{#if this.reliablePush.canEnable}}
            <button
              type="button"
              class="btn btn-default"
              disabled={{this.reliablePush.busy}}
              {{on "click" this.reliablePush.connect}}
            >{{i18n "discourse_reliable_push.connect"}}</button>
          {{/if}}
          <button
            type="button"
            class="btn btn-default"
            disabled={{this.reliablePush.busy}}
            {{on "click" this.reliablePush.verify}}
          >{{i18n "discourse_reliable_push.verify"}}</button>
          {{#if this.reliablePush.canTest}}
            <button
              type="button"
              class="btn btn-primary"
              {{on "click" this.reliablePush.sendTest}}
            >{{i18n "discourse_reliable_push.send_test"}}</button>
            <button
              type="button"
              class="btn btn-default"
              {{on "click" this.reliablePush.sendBackgroundTest}}
            >{{i18n "discourse_reliable_push.send_background_test"}}</button>
          {{/if}}
        </div>
        {{#if this.reliablePush.testResult}}
          <p class="reliable-push-status__message" role="status">{{i18n this.reliablePush.testResult}}</p>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
