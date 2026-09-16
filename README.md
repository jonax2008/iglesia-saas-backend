# iglesia-saas-backend

Backend en Supabase (Postgres + Auth + RLS + Edge Functions) para el SaaS de control estadístico de Iglesia.

Plan completo y decisiones de diseño: ver `PLAN.md` en el repo hermano `iglesia-saas` (`Documents/personal/iglesia-saas/PLAN.md`).

## Desarrollo local

Requiere [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) y Docker.

```bash
supabase start   # levanta Postgres, Auth, Storage, Studio, etc. localmente
supabase stop     # detiene el stack local
```

Studio local: http://127.0.0.1:54323

## Migraciones

Las migraciones viven en `supabase/migrations/` y se aplican automáticamente al hacer `supabase start` o `supabase db reset`.

- `20260916000000_catalogos_roles_usuarios.sql` — catálogos base (geográficos, organizacionales, de personas), roles fijos y tabla `usuarios`, con RLS.
- `20260916100000_iglesias_personas_ministros.sql` — tablas `personas`, `iglesias` (con trigger que deriva ciudad/estado/país a partir de la colonia) y `ministros`, columna `usuarios.iglesia_id`, y RLS.

## Bootstrap del primer usuario `super_admin`

Como solo un `super_admin` puede insertar filas en `usuarios` (por RLS), el primer usuario del sistema se crea en dos pasos:

1. Regístrate normalmente desde el frontend (`/signup`) con tu correo real — esto crea la fila en `auth.users` pero **no** crea perfil en `usuarios`.
2. En el SQL Editor del dashboard de Supabase (corre como `postgres`, sin RLS), ejecuta:

   ```sql
   insert into public.usuarios (id, correo, rol_id)
   select id, email, 1 -- 1 = super_admin
   from auth.users
   where email = 'tu-correo@ejemplo.com';
   ```

Después de esto, ese usuario ya puede dar de alta a los demás desde la aplicación.

## Despliegue

```bash
supabase link --project-ref <project-ref>
supabase db push
```
