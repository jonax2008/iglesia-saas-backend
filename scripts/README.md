# Scripts

- `generar_seed_sepomex.py` — genera la migración de municipios/colonias a partir del archivo oficial `CPdescarga.xls` de [correos.gob.mx](https://www.correosdemexico.gob.mx/SSLServicios/ConsultaCP/Descarga.aspx) (Código Postal → Descarga tu código postal). Requiere `pip install xlrd`. El archivo `.xls` no se versiona en el repo (es de ~70MB); se descarga aparte y se referencia por ruta absoluta dentro del script. Solo hace falta volver a correrlo si SEPOMEX publica una actualización del catálogo.
