# WRTDS

# WRTDS — Guía de Replicación

Este directorio contiene los scripts en R para modelar concentraciones de solutos usando **WRTDS** (Weighted Regressions on Time, Discharge, and Season) mediante el paquete `EGRET`. Se modela un parámetro por script, para una subcuenca a la vez.

---

## Estructura de carpetas

```
WRTDS/
├── README.md
│
├── SCRIPTS_WRTDS/
│   ├── 1/                 # Scripts originales (uno por parámetro, una cuenca a la vez)
│   │   ├── ALK.R          ← Alcalinidad
│   │   ├── dSi.R          ← Sílice disuelta
│   │   └── P-PO4.R        ← Fósforo reactivo
│   │
│   └── 2/                 # Pipeline estandarizado (recomendado para el revisor)
│       ├── 00_config.R    ← ÚNICO archivo a editar: rutas + parámetros de todas las cuencas
│       ├── 01_functions.R ← Funciones compartidas (no editar)
│       └── 02_run_all.R   ← Runner principal: ejecuta todas las cuencas en loop
│
├── Datos_Necesarios/      # Datos de entrada con la estructura esperada por los scripts
│   ├── Carr_1/            # Carrera REF
│   │   ├── ALK/
│   │   │   ├── Carr_ref_INFO_ALK.csv
│   │   │   ├── Carr_ref_WRTDS_ALK.csv
│   │   │   └── Q_compilado.csv
│   │   ├── PPO-4/
│   │   │   ├── Carr_ref_INFO_P-PO4.csv
│   │   │   ├── Carr_ref_WRTDS_P-PO4.csv
│   │   │   └── Q_compilado.csv
│   │   └── dSI/
│   │       ├── Carr_ref_INFO_dSi.csv
│   │       ├── Carr_ref_WRTDS_dSi.csv
│   │       └── Q_compilado.csv
│   └── Coy_1/             # Coyhaique REF
│       ├── ALK/           (misma estructura + subcarpeta Results/ con outputs ya generados)
│       ├── P-PO4/
│       └── dSi/
│
└── Resultados/            # Outputs finales organizados por cuenca
    ├── Carr_1/
    │   ├── WRTDS_Output_ALK_REF_CARR.csv
    │   ├── WRTDS_Output_dSi_REF_CARR.csv
    │   └── WRTDS_Output_P-PO4_REF_CARR.csv
    └── Coy_1/
        ├── WRTDS_Output_ALK_REF_COY.csv
        ├── WRTDS_Output_dSi_REF_COY.csv
        └── WRTDS_Output_P-PO4_REF_COY.csv
```

---

## Versiones de los scripts

### Versión 1 — Scripts originales (`SCRIPTS_WRTDS/1/`)

Tres scripts independientes (`ALK.R`, `dSi.R`, `P-PO4.R`), uno por parámetro. Cada script corre una sola cuenca a la vez. Requiere editar `setwd()`, `river_name` y `flow_col` manualmente en cada ejecución.

Útiles para ajuste fino o debugging de una cuenca específica.

### Versión 2 — Pipeline estandarizado (`SCRIPTS_WRTDS/2/`) ← recomendada para replicación

Tres archivos con responsabilidades separadas:

| Archivo        | Rol                                                                 |
|----------------|---------------------------------------------------------------------|
| `00_config.R`  | **Único archivo a editar.** Define `BASE_DIR` y tabla de corridas   |
| `01_functions.R` | Funciones compartidas: carga de datos, preparación, plotting      |
| `02_run_all.R` | Runner: itera sobre todas las cuencas × parámetros en un solo loop  |

Para replicar todas las cuencas: edita `BASE_DIR` en `00_config.R` y ejecuta `02_run_all.R`. Si una cuenca falla, el script continúa con las demás e imprime un resumen al final.

---

## Requisitos

```r
if (!requireNamespace("pacman")) install.packages("pacman")
pacman::p_load(tidyverse, lubridate, EGRET, EGRETci, dataRetrieval, glue, purrr)
```

R 4.0 o superior.

---

## Estructura de datos de entrada

Cada ejecución necesita **tres archivos CSV** en una subcarpeta por parámetro:

### 1. Archivo INFO (`*_INFO_<param>.csv`)

Metadatos de la estación y parámetro. Una sola fila con estas columnas:

| Columna         | Descripción                          | Ejemplo         |
|-----------------|--------------------------------------|-----------------|
| `param.units`   | Unidades del parámetro               | `Mg/l`          |
| `shortName`     | Nombre corto de la estación          | `Carrera_Ref`   |
| `paramShortName`| Nombre corto del parámetro           | `ALK`           |
| `constitAbbrev` | Abreviación del constituyente        | `ALK`           |
| `drainSqKm`     | Área de cuenca (km²)                 | `12.5`          |
| `station.nm`    | Nombre completo de la estación       | `Carrera Ref`   |
| `param.nm`      | Nombre completo del parámetro        | `Alkalinity`    |
| `staAbbrev`     | Abreviación de la estación           | `CArr_ref`      |

### 2. Archivo de muestras (`*_WRTDS_<param>.csv`)

Series de concentración medida en terreno:

```
Date,remarks,<PARAMETRO>
2016-10-08,,14.01
2016-11-19,,16.77
2017-01-08,,21.05
```

- `Date`: formato `YYYY-MM-DD`
- `remarks`: generalmente vacío
- `<PARAMETRO>`: columna con el nombre del parámetro (`ALK`, `dSi`, o `Conc` para P-PO4)
- El separador decimal puede ser coma (se corrige automáticamente en el script)

### 3. Caudal diario (`Q_compilado.csv`)

Series de caudal diario compiladas (output de la etapa de pre-procesado):

```
Date,Carrera_Imp1,Carrera_Imp2,Carrera_Ref,Coyhaique_Imp1,Coyhaique_Imp2,Coyhaique_Ref
2016-09-11,108.12,NA,104.19,8.10,NA,16.53
2016-09-12,99.50,NA,96.71,8.22,NA,16.84
```

- Una columna por subcuenca; el script selecciona la columna correcta según el parámetro `flow_col`
- Caudal en m³/s
- `NaN` donde no hay dato

---

## Configuración antes de correr

### Usando los scripts de la versión 1 (`1/`)

Al inicio de cada script hay una sección de configuración que **debe ajustarse** para cada subcuenca:

```r
# --- AJUSTAR ANTES DE CORRER ---
setwd("/ruta/a/tu/carpeta/de/subcuenca/")  # ← directorio de la cuenca

PARAM_NAME  <- "ALK"           # nombre del parámetro
river_name  <- "Carrera_Ref"   # nombre de la subcuenca
flow_col    <- "Carrera_Ref"   # columna de Q en Q_compilado.csv
```

Los archivos de entrada se buscan relativos al `setwd()`:

| Script  | INFO                             | Muestras                        | Caudal               |
|---------|----------------------------------|---------------------------------|----------------------|
| ALK.R   | `ALK/<estacion>_INFO_ALK.csv`    | `ALK/<estacion>_WRTDS_ALK.csv`  | `ALK/Q_compilado.csv`  |
| dSi.R   | `dSi/<estacion>_INFO_dSi.csv`    | `dSi/<estacion>_WRTDS_dSi.csv`  | `dSi/Q_compilado.csv`  |
| P-PO4.R | `P-PO4/<estacion>_INFO_P-PO4.csv`| `P-PO4/<estacion>_WRTDS_PPO4.csv`| `P-PO4/Q_compilado.csv`|

### Usando el pipeline de la versión 2 (`2/`) ← recomendado

1. Abrir `00_config.R` y cambiar **solo** `BASE_DIR`:
   ```r
   BASE_DIR <- "/ruta/a/tu/directorio/raiz"
   ```
2. Verificar que la tabla `runs` (en el mismo archivo) coincide con tus nombres de archivos.
3. Ejecutar `02_run_all.R` desde RStudio (`Source`) o terminal:
   ```bash
   Rscript SCRIPTS_WRTDS/2/02_run_all.R
   ```

---

## Descripción de cada script

### `ALK.R` — Alcalinidad

Script base. Ajusta un modelo WRTDS con parámetros fijos seguido de suavizado Kalman.

**Parámetros del modelo:**

| Parámetro   | Valor | Descripción                        |
|-------------|-------|------------------------------------|
| `windowY`   | 8     | Ventana temporal (años)            |
| `windowQ`   | 2     | Ventana de caudal (unidades log)   |
| `windowS`   | 0.75  | Ventana estacional                 |
| `minNumObs` | 10    | Mínimo de observaciones            |
| `rho`       | 0.95  | Correlación temporal Kalman        |

---

### `dSi.R` — Sílice disuelta

Similar a ALK pero incluye conversión de unidades. Si los datos vienen en µM, el script multiplica por `DSI_FACTOR = 0.06008` para convertir a mg/L. Si ya están en mg/L, ajustar ese factor a `1`.

**Parámetros del modelo:**

| Parámetro   | Valor | Descripción                        |
|-------------|-------|------------------------------------|
| `windowY`   | 4     | Ventana temporal (años)            |
| `windowQ`   | 3.1   | Ventana de caudal (unidades log)   |
| `windowS`   | 0.38  | Ventana estacional                 |
| `minNumObs` | 6     | Mínimo de observaciones            |
| `rho`       | 0.9   | Correlación temporal Kalman        |

---

### `P-PO4.R` — Fósforo reactivo

Script más complejo. Diseñado para parámetros con alta variabilidad y riesgo de picos espurios. Incorpora:

- **Búsqueda automática de parámetros** (`grid search`): evalúa 6 combinaciones de ventanas y selecciona la que minimiza una función objetivo que penaliza picos extremos
- **Winsorización del caudal**: acota Q a [p5, p95] para evitar extrapolación en eventos extremos
- **Kalman condicional**: solo se aplica si el modelo base no presenta picos descontrolados (ratio ≤ 1.20)
- **Fallback ultra-suave**: si el modelo sigue generando picos (ratio > 1.50), aplica ventanas muy amplias para forzar suavidad
- **Unidades**: convierte automáticamente de µg/L a mg/L

Los parámetros del grid search y los umbrales de spike se pueden ajustar en la sección de configuración al inicio del script.

---

## Outputs generados

### Archivos por ejecución (dentro del `setwd()` de cada script)

Cada script crea una subcarpeta dentro de `Results/` con tres archivos:

```
Results/
└── {river_name}_{param}_WRTDS/
    ├── modelResults_{param}.rds          ← objeto EGRET completo (para análisis en R)
    ├── WRTDS_Output_{param}.csv          ← estimaciones diarias
    └── Fig_{param}_obs_vs_model.png      ← gráfico observado vs. modelado
```

### Resultados finales (`Resultados/`)

Los CSV de estimaciones diarias finales están organizados por cuenca:

```
Resultados/
├── Carr_1/                               ← Cuenca Carrera (estación Ref)
│   ├── WRTDS_Output_ALK_REF_CARR.csv
│   ├── WRTDS_Output_dSi_REF_CARR.csv
│   └── WRTDS_Output_P-PO4_REF_CARR.csv
└── Coy_1/                               ← Cuenca Coyhaique (estación Ref)
    ├── WRTDS_Output_ALK_REF_COY.csv
    ├── WRTDS_Output_dSi_REF_COY.csv
    └── WRTDS_Output_P-PO4_REF_COY.csv
```

### Columnas de los archivos `WRTDS_Output_*.csv`

| Columna     | Descripción                                          |
|-------------|------------------------------------------------------|
| `Date`      | Fecha                                                |
| `Q`         | Caudal diario (m³/s)                                 |
| `LogQ`      | log(Q)                                               |
| `DecYear`   | Año decimal                                          |
| `yHat`      | Predicción del modelo en escala log                  |
| `SE`        | Error estándar de la predicción                      |
| `ConcDay`   | Concentración estimada diaria (mg/L)                 |
| `FluxDay`   | Flujo de masa estimado diario                        |
| `FNConc`    | Concentración flow-normalized                        |
| `FNFlux`    | Flujo flow-normalized                                |
| `GenConc`   | Concentración generalizada (sin tendencia temporal)  |
| `GenFlux`   | Flujo generalizado                                   |

> `FNConc` y `FNFlux` requieren Kalman completado para calcularse; pueden aparecer como `NA` si el modelo no convergió en esa etapa.

---

## Cómo replicar el proceso paso a paso

### Opción A — Pipeline estandarizado (versión 2, recomendada)

1. Copiar los datos de entrada en la estructura `Datos_Necesarios/` (o ajustar rutas en `00_config.R`)
2. Editar `BASE_DIR` en `00_config.R`
3. Revisar la tabla `runs` en `00_config.R` y verificar que los nombres de archivo coincidan
4. Ejecutar `02_run_all.R` — genera todos los resultados en `Resultados/` de forma automática

### Opción B — Scripts individuales (versión 1)

1. **Preparar carpeta de trabajo** para cada subcuenca con la estructura de `Datos_Necesarios/`
2. **Verificar los tres CSVs** de entrada (INFO, muestras, Q_compilado)
3. **Abrir el script** del parámetro correspondiente y ajustar `setwd()`, `river_name` y `flow_col`
4. **Verificar la conversión de unidades** (`DSI_FACTOR` en dSi.R; los datos de P-PO4 deben estar en µg/L)
5. **Correr el script** completo desde RStudio o terminal:
   ```bash
   Rscript SCRIPTS_WRTDS/1/ALK.R
   ```
6. **Revisar el gráfico** generado para validar visualmente el ajuste
7. Los resultados quedan en `Results/` dentro del `setwd()` definido

> Los tres scripts son independientes entre sí y pueden correrse en cualquier orden.

---

## Notas sobre formatos y locale

- Los scripts detectan y corrigen automáticamente comas como separador decimal (formato español/europeo)
- Las fechas deben estar en formato `YYYY-MM-DD`
- Q negativo o cero se elimina automáticamente antes del modelado
- Fechas duplicadas en las muestras: ALK y dSi usan la primera ocurrencia; P-PO4 promedia los duplicados
