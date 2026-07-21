# Discourse Reliable Push — исправленная версия

Плагин создаёт собственный надёжный контур доставки Web Push для Discourse:

```text
событие → определение получателей → Delivery/Attempt outbox → Web Push
                                      ↘ ACK received/opened
                                      ↘ MessageBus: звук и мигание вкладки
```

Версия в этом архиве: **0.3.0**.

## Что исправлено

### Новые сообщения и темы

Первая версия ожидала, что Discourse создаст персональное уведомление для каждого обычного сообщения. Это неверно для режимов «Следить» и «Уведомлять»: там стандартное персональное уведомление создаётся только для ответа/упоминания.

Теперь плагин использует `post_alerter_after_save_post` и самостоятельно делает fanout:

- первый пост → `new_topic`;
- последующие посты → `topic_post`;
- получатели — все пользователи с Push-подпиской, кроме автора;
- исключаются пользователи, которые не видят тему;
- учитываются mute темы, категории и тегов;
- учитывается `watched_precedence_over_muted`;
- повторная проверка ACL/mute/DND выполняется непосредственно перед отправкой.

Таким образом, «незаглушённая тема» означает не только `TopicUser != muted`, но и отсутствие действующего заглушения категории/тега.

### Подписки браузеров

Fanout раньше зависел от отдельной таблицы плагина. Если пользователь не открыл сайт после установки, его стандартная `PushSubscription` не попадала в эту таблицу и доставка заканчивалась `no_subscription`.

Теперь:

- получатели выбираются как по стандартным `PushSubscription`, так и по зеркалу плагина;
- перед доставкой стандартные подписки автоматически импортируются;
- клиент дополнительно синхронизирует текущую подписку;
- при появлении подписки повторно запускаются свежие доставки `no_subscription`.

### Устойчивость очереди и параллельное выполнение

Исправлены гонки, из-за которых повторные Sidekiq jobs могли отправить один и тот же payload дважды или понизить состояние уже подтверждённой доставки:

- подготовка `Delivery` и отправка `Attempt` захватываются атомарным SQL-переходом состояния;
- `accepted → received → opened` не понижается поздними ответами другого устройства;
- повышение приоритета semantic duplicate выполняется под блокировкой строки;
- ошибки одного устройства не переводят успешно доставленное событие в `failed`;
- зависшие `pending`/`preparing`/`sending` и просроченные `retrying` записи восстанавливаются плановым job каждые 10 минут;
- исчерпанные или отключённые endpoints завершают логическую доставку, а не оставляют её навсегда в `preparing`;
- счётчик ошибок подписки обновляется атомарно;
- server-side mirror не может присвоить endpoint, уже подтверждённый другим вошедшим пользователем.

Контур даёт **at-least-once** доставку. При сетевом тайм-ауте после фактического принятия Push-сервисом теоретически возможен повтор: Web Push не предоставляет транзакционного exactly-once подтверждения. `tag` и semantic dedupe уменьшают визуальные дубли.

### Перехват стандартного Web Push

Исправлена опасная семантика `:skipped`: старая версия могла подавить стандартный Push даже при ошибке/неполной обработке.

Новая логика:

- `handled` — событие записано в outbox, стандартный sender не вызывается;
- `suppressed` — событие намеренно отключено DND/настройкой;
- `failed` — обязательный fallback в `PushNotificationPusher.push`;
- исключение в плагине — обязательный fallback в core.

`reliable_push_replace_core_web_push` теперь по умолчанию **false**. Включать его следует только после проверки подписок и тестовой доставки.

### События

Реализованы отдельные категории событий:

- сообщения Chat;
- упоминания, ответы и цитаты;
- личные сообщения;
- все новые сообщения в незаглушённых темах;
- новые темы;
- новые категории;
- награды;
- события аккаунта;
- прочие стандартные и plugin-defined `Notification`;
- вход пользователей в комнаты Resenha.

Для каждой категории есть site setting и пользовательская настройка в `reliable_push_preferences`.

### Resenha

Текущая реализация Resenha обновляет `ParticipantTracker`, но не публикует стабильное событие входа. Плагин:

1. поддерживает будущие события `resenha_user_joined_room` и `resenha_participant_joined`;
2. при наличии Resenha безопасно добавляет адаптер к `Resenha::ParticipantTracker.add`;
3. отличает новый вход от очередного presence refresh;
4. использует временное окно дедупликации;
5. проверяет `Guardian#can_see_resenha_room?`;
6. исключает вошедшего пользователя из получателей.

Для ограничения аудитории задайте `reliable_push_resenha_group_ids`.

### DND, звук и мигание вкладки

- DND проверяется через доступный API текущей версии Discourse (`do_not_disturb?`/`in_do_not_disturb?`) либо по активному интервалу `do_not_disturb_timings` — при создании и непосредственно перед отправкой.
- Открытая вкладка получает событие через приватный MessageBus-канал.
- После первого действия пользователя в браузере Web Audio воспроизводит короткий сигнал.
- При скрытой вкладке заголовок мигает и показывает число новых событий.
- При возврате во вкладку заголовок восстанавливается.
- Для фонового браузера и Android/PWA используется Web Push Discourse.

Ограничение платформы: браузеры не разрешают произвольно воспроизводить звук до первого жеста пользователя. Системный звук закрытой вкладки определяется браузером/Android/ОС; Web Push не гарантирует пользовательский аудиофайл.

## Установка

В `app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/DaOver0/discourse-reliable-push.git
```

Для проверки архива скопируйте папку в:

```text
/var/discourse/containers/app.yml → plugins/discourse-reliable-push
```

После замены исходников:

```bash
cd /var/discourse
./launcher rebuild app
```

Миграции создадут:

- `reliable_push_subscriptions`;
- `reliable_push_deliveries`;
- `reliable_push_attempts`;
- `reliable_push_preferences`.

## Безопасное включение

### Этап 1 — транспорт работает параллельно core

```text
reliable_push_enabled = true
reliable_push_replace_core_web_push = false
reliable_push_topic_events_enabled = true
reliable_push_topic_posts_enabled = true
reliable_push_new_topics_enabled = true
```

Откройте сайт пользователем с разрешёнными Push-уведомлениями. Затем проверьте:

```text
GET /reliable-push/status
```

Ожидается `active_subscriptions > 0`.

Создайте сообщение другим пользователем. В Rails console:

```ruby
user = User.find_by(username: "recipient")
ReliablePush::Delivery.where(user_id: user.id).order(id: :desc).limit(20).pluck(
  :id, :kind, :state, :last_error
)
```

### Этап 2 — заменить core sender

Когда сообщения, чат и упоминания успешно проходят состояния `accepted`/`received`:

```text
reliable_push_replace_core_web_push = true
```

После этого стандартные персональные Web Push события проходят через outbox плагина. Внутренний список уведомлений Discourse и MessageBus не удаляются: они остаются источником UI и непрочитанных счётчиков, а отправка Web Push заменяется.

## Диагностика состояний

| Состояние | Значение |
|---|---|
| `pending` | событие создано |
| `preparing` | подписки найдены, создаются попытки |
| `accepted` | Push-сервис принял сообщение |
| `received` | service worker получил payload |
| `opened` | пользователь нажал уведомление |
| `no_subscription` | активной подписки нет |
| `cancelled` | DND, preference, ACL или mute запретили отправку |
| `failed` | попытки исчерпаны |
| `expired` | истёк TTL |

Администраторский статус:

```text
GET /reliable-push/admin/status
```

## Пользовательские настройки

JSON API:

```http
GET /reliable-push/preferences
```

```http
PUT /reliable-push/preferences
Content-Type: application/json

{
  "preferences": {
    "topic_posts": true,
    "new_topics": true,
    "chat_messages": true,
    "mentions_replies": true,
    "private_messages": true,
    "badges": true,
    "account_events": true,
    "new_categories": true,
    "resenha": true,
    "other": true,
    "sound": true,
    "tab_blink": true
  }
}
```

В браузере плагин также предоставляет:

```javascript
await ReliablePushPreferences.load();
await ReliablePushPreferences.save({ topic_posts: false, sound: true });
```

Серверная модель и API пользовательских настроек готовы. Графическая форма в профиле намеренно не включена: outlet страницы настроек меняется между версиями Discourse, а без запуска на целевой версии непроверенный Glimmer-коннектор мог бы сломать клиентскую сборку. До добавления проверенной формы настройки доступны через API и `ReliablePushPreferences`.

## Проверка вручную

Используйте двух пользователей и два браузерных профиля.

1. Получатель разрешает уведомления и имеет `active_subscriptions > 0`.
2. Отправитель создаёт обычный ответ без `@mention`.
3. Для получателя тема, категория и теги не заглушены.
4. Получатель не находится в DND.
5. Проверяется `Delivery.kind == "topic_post"`.
6. Проверяется `Attempt.state == "accepted"`.
7. Проверяется ACK `received`.
8. Повторяется тест для первой публикации новой темы.
9. Повторяется для read-restricted категории с пользователем без доступа: доставка не должна создаваться/отправляться.
10. Повторяется с muted category и watched topic при обоих значениях `watched_precedence_over_muted`.

## Автоматические проверки в архиве

Перед упаковкой выполнены:

```bash
ruby -c                  # для каждого Ruby-файла
YAML.load_file           # settings и locale
node --check             # initializer и service worker
require_relative audit   # все локальные пути из plugin.rb существуют
unzip -t                 # проверка целостности итогового архива
```

Подробный отчёт находится в `VALIDATION.md`.

Полные RSpec/integration tests требуют checkout совместимой версии Discourse, PostgreSQL, Redis и установленных Chat/Resenha. Они не могут подтвердиться одной только статической проверкой плагина.

## Важные замечания по нагрузке

Требование «каждый новый пост всем пользователям, у которых контекст не muted» создаёт fanout порядка:

```text
число новых постов × число Push-пользователей
```

На большом форуме это дорого. Используйте:

- `reliable_push_max_fanout`;
- `reliable_push_topic_group_ids`;
- ограничение TTL;
- мониторинг Sidekiq;
- retention cleanup;
- пользовательские preferences.

## Лицензия

MIT — см. `LICENSE`.
