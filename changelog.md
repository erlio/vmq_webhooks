# Changelog

## vmq_webhooks 0.2.0

Backwards incompatible changes:

 - base64 encode MQTT payloads by default.
 - In all hooks `subscriber_id` has been renamed to `client_id` to be consistent
   with VerneMQ and other plugins where a `subscriber_id` is defined as a
   mountpoint and a client id.
 - `on_offline_message` now also passes `qos`, `topic`, `payload` and `retain`
   fields as part of the JSON message. Note, that this change **requires VerneMQ
   0.15.2 or newer to work**.

Other changes:

 - Webhooks can be persisted across broker restarts by adding them to the
   `priv/vmq_webhooks.conf` file.


## vmq_webhooks 0.1.0

Initial version.
