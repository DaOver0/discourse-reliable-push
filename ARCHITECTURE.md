# Архитектура Reliable Push 0.3.0

## 1. Event adapters

Источники:

- `PushNotificationPusher.push` — стандартные персональные Web Push события;
- `notification_created` — persisted account/plugin events;
- `post_alerter_after_save_post` — новый topic/post fanout;
- `category_created` — новые категории;
- Resenha `ParticipantTracker.add` или стабильное upstream событие.

Адаптеры не отправляют Web Push напрямую. Они вызывают `EventIngestor`.

## 2. Semantic event and deduplication

`EventIngestor` создаёт один `Delivery` на пользователя и semantic key:

- `post:<post_id>`;
- `chat:<type>:<chat_message_id>`;
- `notification:<notification_id>`;
- `category:created:<category_id>`;
- `resenha:join:<room_id>:<user_id>:<time_bucket>`.

Персональное событие с более высоким приоритетом обновляет payload уже существующего broadcast-события.

## 3. Recipient policy

`RecipientScope` определяет кандидатов по стандартным и зеркальным Push-подпискам.

`AccessChecker` проверяет:

- active/approved/non-staged/non-bot/non-suspended;
- DND;
- user preference;
- Guardian ACL;
- автора сообщения;
- TopicUser mute;
- CategoryUser mute;
- TagUser mute;
- `watched_precedence_over_muted`;
- доступ к Resenha room.

Проверка выполняется дважды: при ingestion/fanout и перед Web Push.

## 4. Durable outbox

`Delivery` — логическое событие для пользователя.

`Attempt` — отдельная попытка для каждого браузера/PWA устройства.

Состояния:

```text
Delivery: pending → preparing → accepted → received → opened
                     ↘ no_subscription / cancelled / failed / expired

Attempt:  pending → sending → accepted
                       ↘ retrying → ...
                       ↘ failed / expired / cancelled
```

Повторы используют exponential backoff с jitter. HTTP 404/410 отключают подписку.

Переходы `pending/no_subscription → preparing` и `pending/retrying → sending` выполняются атомарными SQL-claims. Это защищает от параллельной обработки дублированных Sidekiq jobs. Плановый `ReliablePushRecoverStaleAttempts` возвращает зависшие `pending`/`preparing`/`sending` и просроченные `retrying` записи в рабочую очередь; условные UPDATE не могут перезаписать уже завершившийся конкурентный переход.

Состояние `Delivery` монотонно для успешного пути: поздний `accepted` не понижает `received/opened`. Сбой одного endpoint не понижает логическую доставку, если другое устройство уже принято Push-сервисом.

## 5. Subscription bridge

`Subscription.mirror_core_for_user!` импортирует стандартные `PushSubscription` без ожидания, пока пользователь снова откроет сайт.

Клиентская синхронизация поддерживает актуальность endpoint/keys и повторно запускает свежие `no_subscription`/`failed` доставки. Явная синхронизация текущего вошедшего браузера может переназначить endpoint его фактическому владельцу; фоновое зеркало core-подписки работает в безопасном режиме и не отбирает endpoint у другого пользователя.

## 6. Presentation

Фоновый канал:

```text
Delivery → WebPush → browser/PWA service worker → native notification
```

Открытая вкладка:

```text
Delivery → private MessageBus channel → sound + blinking document.title
```

Service worker отправляет ACK по непрогнозируемому token, а не по авторизованной cookie-сессии.

## 7. Fail-open migration

До включения `reliable_push_replace_core_web_push` core sender остаётся активным.

После включения:

- `handled` и `suppressed` не вызывают core sender;
- `failed` и исключения вызывают `super`.

Это предотвращает потерю уведомления при сбое плагина.
