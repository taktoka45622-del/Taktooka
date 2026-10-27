Banners use a 16:9 frame in the dashboard and Flutter app. Dashboard delete requires confirmation and verifies the deleted row. The existing admin RLS policy still controls DELETE. Applied on the current project:

```sql
grant delete on public.x_banners to authenticated;
```

Category targets use xspace://category/<category UUID> in the existing target_url column. External destinations remain HTTP/HTTPS URLs. Old HTTP/HTTPS banners continue working. Internal destinations require app 2.0.8+28. Image storage objects remain untouched when deleting a banner.

Validation: build, existing DOM tests, 12 banner form/confirmation tests, live table privilege/RLS checks. Flutter SDK unavailable; app changes need local build/device verification.
