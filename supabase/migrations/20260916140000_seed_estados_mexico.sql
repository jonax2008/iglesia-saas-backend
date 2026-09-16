-- Seed de los 32 estados oficiales de México (dato estable, no requiere
-- el archivo de SEPOMEX). Municipios y colonias/CP se importarán en un
-- paso aparte a partir del catálogo oficial de SEPOMEX cuando esté
-- disponible (ver PLAN.md).
insert into public.estados (nombre, pais_id)
select nombre, (select id from public.paises where nombre = 'México')
from unnest(array[
  'Aguascalientes', 'Baja California', 'Baja California Sur', 'Campeche',
  'Chiapas', 'Chihuahua', 'Ciudad de México', 'Coahuila', 'Colima', 'Durango',
  'Estado de México', 'Guanajuato', 'Guerrero', 'Hidalgo', 'Jalisco',
  'Michoacán', 'Morelos', 'Nayarit', 'Nuevo León', 'Oaxaca', 'Puebla',
  'Querétaro', 'Quintana Roo', 'San Luis Potosí', 'Sinaloa', 'Sonora',
  'Tabasco', 'Tamaulipas', 'Tlaxcala', 'Veracruz', 'Yucatán', 'Zacatecas'
]) as nombre
on conflict do nothing;
