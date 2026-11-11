-- Supabase Storage policy layer, applied only to the separate app project.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('kitchen-media','kitchen-media',false,10485760,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
create policy cc_media_read on storage.objects for select to authenticated
using(bucket_id='kitchen-media' and exists(select 1 from public.cc_media m where m.object_key=name and m.status='uploaded' and app_private.member(m.kitchen_id)));
-- No generic client upload/update policy. Signed upload URLs are issued by the
-- authenticated server after creation of a pending cc_media asset record. The
-- completion worker verifies actual size/hash/MIME before setting uploaded.
