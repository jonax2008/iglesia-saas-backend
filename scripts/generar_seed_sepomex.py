import xlrd
import sys

XLS_PATH = "/Users/jmurrietag/Documents/personal/iglesia-saas/CPdescarga.xls"
OUT_PATH = "/Users/jmurrietag/Documents/personal/iglesia-saas/iglesia-saas-backend/supabase/migrations/20260916160000_seed_sepomex_municipios_colonias.sql"

MAPA_ESTADOS = {
    "Aguascalientes": "Aguascalientes",
    "Baja California": "Baja California",
    "Baja California Sur": "Baja California Sur",
    "Campeche": "Campeche",
    "Coahuila de Zaragoza": "Coahuila",
    "Colima": "Colima",
    "Chiapas": "Chiapas",
    "Chihuahua": "Chihuahua",
    "Ciudad de México": "Ciudad de México",
    "Durango": "Durango",
    "Guanajuato": "Guanajuato",
    "Guerrero": "Guerrero",
    "Hidalgo": "Hidalgo",
    "Jalisco": "Jalisco",
    "México": "Estado de México",
    "Michoacán de Ocampo": "Michoacán",
    "Morelos": "Morelos",
    "Nayarit": "Nayarit",
    "Nuevo León": "Nuevo León",
    "Oaxaca": "Oaxaca",
    "Puebla": "Puebla",
    "Querétaro": "Querétaro",
    "Quintana Roo": "Quintana Roo",
    "San Luis Potosí": "San Luis Potosí",
    "Sinaloa": "Sinaloa",
    "Sonora": "Sonora",
    "Tabasco": "Tabasco",
    "Tamaulipas": "Tamaulipas",
    "Tlaxcala": "Tlaxcala",
    "Veracruz de Ignacio de la Llave": "Veracruz",
    "Yucatán": "Yucatán",
    "Zacatecas": "Zacatecas",
}


def esc(s):
    return s.replace("'", "''")


def main():
    wb = xlrd.open_workbook(XLS_PATH)

    municipios = set()  # (estado_nombre, municipio)
    colonias = set()  # (estado_nombre, municipio, colonia, cp)
    sin_mapear = set()

    for sheet_name in wb.sheet_names():
        if sheet_name == "Nota":
            continue
        sh = wb.sheet_by_name(sheet_name)
        for r in range(1, sh.nrows):
            cp = str(sh.cell_value(r, 0)).strip()
            colonia = str(sh.cell_value(r, 1)).strip()
            municipio = str(sh.cell_value(r, 3)).strip()
            estado_sepomex = str(sh.cell_value(r, 4)).strip()

            estado = MAPA_ESTADOS.get(estado_sepomex)
            if estado is None:
                sin_mapear.add(estado_sepomex)
                continue
            if not (cp and colonia and municipio):
                continue

            municipios.add((estado, municipio))
            colonias.add((estado, municipio, colonia, cp))

    if sin_mapear:
        print("ERROR: estados sin mapear:", sin_mapear, file=sys.stderr)
        sys.exit(1)

    municipios = sorted(municipios)
    colonias = sorted(colonias)

    print(f"Municipios únicos: {len(municipios)}")
    print(f"Colonias únicas: {len(colonias)}")

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        f.write(
            "-- Seed de municipios y colonias desde el catálogo oficial de SEPOMEX\n"
            "-- (CPdescarga.xls, descargado de correos.gob.mx). Generado por\n"
            "-- scratchpad/generar_seed_sepomex.py, no editar a mano.\n\n"
            "alter table public.colonias\n"
            "  add constraint colonias_ciudad_nombre_cp_key unique (ciudad_id, nombre, codigo_postal);\n\n"
        )

        # --- Municipios (ciudades) ---
        CHUNK = 5000
        for i in range(0, len(municipios), CHUNK):
            chunk = municipios[i : i + CHUNK]
            values = ",\n".join(
                f"  ('{esc(mun)}', '{esc(edo)}')" for edo, mun in chunk
            )
            f.write(
                "insert into public.ciudades (nombre, estado_id)\n"
                "select v.municipio, e.id\n"
                "from (values\n"
                f"{values}\n"
                ") as v(municipio, estado_nombre)\n"
                "join public.estados e on e.nombre = v.estado_nombre\n"
                "on conflict (estado_id, nombre) do nothing;\n\n"
            )

        # --- Colonias ---
        for i in range(0, len(colonias), CHUNK):
            chunk = colonias[i : i + CHUNK]
            values = ",\n".join(
                f"  ('{esc(col)}', '{esc(cp)}', '{esc(mun)}', '{esc(edo)}')"
                for edo, mun, col, cp in chunk
            )
            f.write(
                "insert into public.colonias (nombre, codigo_postal, ciudad_id)\n"
                "select v.colonia, v.cp, c.id\n"
                "from (values\n"
                f"{values}\n"
                ") as v(colonia, cp, municipio, estado_nombre)\n"
                "join public.estados e on e.nombre = v.estado_nombre\n"
                "join public.ciudades c on c.estado_id = e.id and c.nombre = v.municipio\n"
                "on conflict (ciudad_id, nombre, codigo_postal) do nothing;\n\n"
            )

    print(f"Escrito: {OUT_PATH}")


if __name__ == "__main__":
    main()
