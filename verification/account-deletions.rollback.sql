create or replace function pg_temp.account_deletion_qa() returns jsonb language plpgsql as $qa$
declare owner_id uuid;u uuid:=gen_random_uuid();a uuid:=gen_random_uuid();j jsonb;p jsonb;r jsonb:='[]';err text;kind text;ids uuid[]:='{}';n integer;
begin
 begin
 select x.user_id into strict owner_id from public.tkt_admins x join public.tkt_profiles q using(user_id)where not q.blocked and q.deleted_at is null limit 1;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 p:=tkt_private.admin_delete_preview('user',owner_id,owner_id);
 select count(*)into n from public.tkt_admins x join public.tkt_profiles q using(user_id)where not q.blocked and q.deleted_at is null;
 r:=r||jsonb_build_object('test','last active owner protection','passed',(p->'blockers'?'LAST_OWNER')=(n=1));
 foreach kind in array array['customer','captain','staff','owner','exchange'] loop
  u:=gen_random_uuid();ids:=array_append(ids,u);a:=gen_random_uuid();
  insert into auth.users(id,email,aud,role)values(u,'qa-delete-'||u||'@accounts.taktooka.invalid','authenticated','authenticated');
  insert into public.tkt_profiles(user_id,name,phone,captain)values(u,'QA deletion fixture','+96479'||lpad((floor(random()*100000000)::bigint)::text,8,'0'),kind='captain');
  if kind='staff'then insert into tkt_private.staff_accounts(user_id,name,phone,email,permissions,active,created_by)values(u,'QA deletion staff','+96478'||lpad((floor(random()*100000000)::bigint)::text,8,'0'),'qa-'||u||'@taktooka.internal','{}',true,owner_id);end if;
  if kind='owner'then insert into public.tkt_admins(user_id)values(u);end if;
  if kind='exchange'then insert into tkt_private.exchange_agents(id,name,phone,pin_hash,user_id)values(a,'QA deletion exchange',u::text,'unusable',u);end if;
  p:=tkt_private.admin_delete_preview('user',u,owner_id);
  r:=r||jsonb_build_object('test',kind||' type resolved','passed',p->>'account_type'=kind);
  err:=null;begin perform public.tkt_admin_account_delete('prepare',jsonb_build_object('kind','user','id',u,'fingerprint','wrong'),owner_id);exception when others then err:=sqlerrm;end;
  r:=r||jsonb_build_object('test',kind||' confirmation fingerprint checked','passed',err='ACCOUNT_CHANGED');
  if kind='customer'then
   insert into tkt_private.wallets(user_id,balance)values(u,100);
   err:=null;begin perform public.tkt_admin_account_delete('prepare',jsonb_build_object('kind','user','id',u,'fingerprint',p->>'fingerprint'),owner_id);exception when others then err:=sqlerrm;end;
   r:=r||jsonb_build_object('test','nonzero wallet blocks deletion','passed',err='SETTLE_BALANCE');update tkt_private.wallets set balance=0 where user_id=u;
   err:=null;begin perform tkt_private.admin_delete_preview('user',owner_id,u);exception when others then err:=sqlerrm;end;
   r:=r||jsonb_build_object('test','nonowner rejected','passed',err='OWNER_REQUIRED');
  end if;
  j:=public.tkt_admin_account_delete('prepare',jsonb_build_object('kind','user','id',u,'fingerprint',p->>'fingerprint'),owner_id);
  r:=r||jsonb_build_object('test',kind||' prepare blocks access','passed',(select blocked from public.tkt_profiles where user_id=u)and not exists(select 1 from public.tkt_admins where user_id=u)and not exists(select 1 from tkt_private.staff_accounts where user_id=u));
  p:=public.tkt_admin_account_delete('prepare',jsonb_build_object('kind','user','id',u,'fingerprint','retry'),owner_id);
  r:=r||jsonb_build_object('test',kind||' retry same job','passed',p->>'id'=j->>'id');
  perform public.tkt_admin_account_delete('purge',jsonb_build_object('job_id',j->>'id'),owner_id);
  perform public.tkt_admin_account_delete('finish',jsonb_build_object('job_id',j->>'id'),owner_id);
  r:=r||jsonb_build_object('test',kind||' purge and finish','passed',(select deleted_at is not null and blocked and phone=''and name='حساب محذوف'from public.tkt_profiles where user_id=u)and(select status='completed'from tkt_private.admin_account_deletions where id=(j->>'id')::uuid));
  err:=null;begin perform public.tkt_manage('restore',jsonb_build_object('kind','user','entity_id',u));exception when others then err:=sqlerrm;end;
  r:=r||jsonb_build_object('test',kind||' cannot restore deleted account','passed',err='ACCOUNT_DELETED');
  p:=public.tkt_account_admin('list',jsonb_build_object('search',u::text));
  r:=r||jsonb_build_object('test',kind||' removed from account list','passed',jsonb_array_length(p)=0);
 end loop;
 a:=gen_random_uuid();insert into tkt_private.exchange_agents(id,name,phone,pin_hash)values(a,'QA legacy deletion',a::text,'unusable');
 p:=tkt_private.admin_delete_preview('exchange',a,owner_id);j:=public.tkt_admin_account_delete('prepare',p,owner_id);
 perform public.tkt_admin_account_delete('purge',jsonb_build_object('job_id',j->>'id'),owner_id);perform public.tkt_admin_account_delete('finish',jsonb_build_object('job_id',j->>'id'),owner_id);
 r:=r||jsonb_build_object('test','legacy exchange deleted','passed',(select deleted_at is not null and not active from tkt_private.exchange_agents where id=a));
 r:=r||jsonb_build_object('test','worker inaccessible to authenticated','passed',not has_function_privilege('authenticated','public.tkt_admin_account_delete(text,jsonb,uuid)','execute'));
 raise exception using errcode='ZX001',message='rollback fixtures';
 exception when sqlstate 'ZX001'then null;end;
 return jsonb_build_object('results',r,'rolled_back',not exists(select 1 from auth.users where id=any(ids)));
end;$qa$;
select pg_temp.account_deletion_qa();
