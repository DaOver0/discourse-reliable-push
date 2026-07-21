# CHANGELOG_FIXES.md

## 0.3.0

- Добавлен обязательный server-side fanout для первого и последующих постов.
- Исправлена причина отсутствия уведомлений у пользователей, чьи core PushSubscription не были синхронизированы.
- Добавлена политика mute темы/категории/тегов с watched precedence.
- Добавлена повторная ACL/DND/preference проверка перед отправкой.
- Исправлен fail-open fallback при ошибках перехвата core Web Push.
- Удалена зависимость новых тем от обязательного списка групп.
- Добавлены новые категории.
- Добавлен Resenha adapter с presence dedupe.
- Resenha adapter теперь инициирует Rails autoload через `safe_constantize`, поэтому не зависит от порядка инициализации плагинов.
- Добавлены user preferences и REST API.
- Исходные миграции 0.2.x сохранены без переписывания; новые индексы и preferences добавлены отдельными upgrade-миграциями.
- Добавлены MessageBus sound/tab blink.
- Исправлены ACK token и извлечение metadata из push/notificationclick.
- Добавлены `received`/`opened` acknowledgements.
- Добавлен exponential retry с jitter.
- Добавлен auto-import стандартных PushSubscription.
- Добавлены status endpoints и cleanup.
- Добавлены русская и английская локализации.
- Добавлена семантическая дедупликация broadcast и persisted Notification по `post:<id>`.
- Более приоритетное персональное событие (упоминание/ответ) обновляет уже созданную broadcast-доставку вместо второго Push.
- Состояния `accepted`/`received`/`opened` сделаны монотонными: поздний ответ Push-сервиса не понижает ACK-состояние.
- Пустой sync одного браузера больше не отключает подписки пользователя на других устройствах.
- Клиентская синхронизация переведена на стандартный `ServiceWorkerRegistration.pushManager` без нестабильного внутреннего импорта Discourse.
- Добавлены regression specs для дедупликации, multi-device sync, mute/ACL, fanout и защиты admin status.
- Персональные события дополнительно захватываются на раннем `push_notification`, до решения core о постановке штатного sender job.
- Добавлены атомарные claims подготовки и отправки, защищающие от дублированных Sidekiq jobs.
- Добавлено восстановление зависших `pending`/`preparing`/`sending` и просроченных `retrying` записей плановым job.
- Исправлена гонка semantic upgrade: приоритет обновляется под блокировкой строки.
- Исправлено зависание доставки в `preparing`, когда все endpoints отключены или исчерпаны.
- Ошибка после принятия payload Push-сервисом больше не переводит `Attempt` обратно в retry.
- Failure counters подписок обновляются атомарно; безопасное core-mirroring не меняет владельца endpoint.
- Добавлены regression specs для восстановления failed-доставки при персональном upgrade и безопасного ownership mirroring.
