# ==============================================================================
#  00_config.R  — ÚNICA SECCIÓN QUE EL REVISOR DEBE EDITAR
#  Modelo WRTDS / WRTDSKalman para cuencas de la Patagonia
# ==============================================================================
#
#  INSTRUCCIONES RÁPIDAS PARA EL REVISOR:
#  1. Cambia BASE_DIR al directorio raíz donde están tus carpetas de datos.
#  2. Revisa la tabla `runs` y asegúrate de que los nombres de archivo
#     corresponden a los archivos que tienes en cada subcarpeta.
#  3. Ejecuta 02_run_all.R (o ábrelo en RStudio y haz "Source").
#
#  Estructura de carpetas esperada dentro de BASE_DIR:
#
#  BASE_DIR/
#  ├── Carrera/
#  │   ├── Carrera_REF/
#  │   │   ├── ALK/
#  │   │   │   ├── Carr_ref_INFO_ALK.csv
#  │   │   │   ├── Carr_ref_WRTDS_ALK.csv
#  │   │   │   └── Q_compilado.csv
#  │   │   ├── dSi/ ...
#  │   │   └── P-PO4/ ...
#  │   ├── Carr_1/ ...
#  │   └── Carr_2/ ...
#  └── Coyhaique/
#      ├── Coy_Ref/ ...
#      ├── Coy_Alt1/ ...
#      └── Coy_Alt2/ ...
#
# ==============================================================================

# ------------------------------------------------------------------------------
# [A] DIRECTORIO RAÍZ  ← CAMBIA ESTO
# ------------------------------------------------------------------------------
BASE_DIR <- "/Users/joaquinfernandez/Documents/Magister/CIEP"

# ------------------------------------------------------------------------------
# [B] TABLA DE CORRIDAS
#     Cada fila = una combinación (cuenca × parámetro).
#     Columnas:
#       run_id       : identificador único (usado en nombre de carpeta de salida)
#       basin_dir    : ruta RELATIVA a BASE_DIR donde están las subcarpetas ALK/, dSi/, etc.
#       river_name   : nombre que aparece en gráficos y archivos de salida
#       param        : "ALK" | "dSi" | "P-PO4"
#       flow_col     : nombre de la columna Q dentro de Q_compilado.csv
#       info_file    : nombre del archivo INFO (dentro de param/)
#       sample_file  : nombre del archivo de muestras (dentro de param/)
#       daily_file   : nombre del Q compilado (dentro de param/)
#       model_type   : "simple" (ALK / dSi) | "grid_search" (P-PO4)
# ------------------------------------------------------------------------------
runs <- data.frame(stringsAsFactors = FALSE,

  run_id      = c(
    "Carr_REF_ALK",   "Carr_REF_dSi",   "Carr_REF_PPO4",
    "Carr_1_ALK",     "Carr_1_dSi",     "Carr_1_PPO4",
    "Carr_2_ALK",     "Carr_2_dSi",     "Carr_2_PPO4",
    "CoyAlt_REF_ALK", "CoyAlt_REF_dSi", "CoyAlt_REF_PPO4",
    "CoyAlt_1_ALK",   "CoyAlt_1_dSi",   "CoyAlt_1_PPO4",
    "CoyAlt_2_ALK",   "CoyAlt_2_dSi",   "CoyAlt_2_PPO4"
  ),

  basin_dir   = c(
    "Modelacion_4/Carrera/Carrera_REF",  "Modelacion_4/Carrera/Carrera_REF",  "Modelacion_3/Coy_alt/Coy_Ref",
    "Modelacion_4/Carrera/Carr_1",       "Modelacion_4/Carrera/Carr_1",       "Modelacion_4/Carrera/Carr_1",
    "Modelacion_4/Carrera/Carr_2",       "Modelacion_4/Carrera/Carr_2",       "Modelacion_4/Carrera/Carr_2",
    "Modelacion_3/Coy_alt/Coy_Ref",      "Modelacion_3/Coy_alt/Coy_Ref",      "Modelacion_3/Coy_alt/Coy_Ref",
    "Modelacion_3/Coy_alt/Coy_Alt1",     "Modelacion_3/Coy_alt/Coy_Alt1",     "Modelacion_3/Coy_alt/Coy_Alt1",
    "Modelacion_3/Coy_alt/Coy_Alt2",     "Modelacion_3/Coy_alt/Coy_Alt2",     "Modelacion_3/Coy_alt/Coy_Alt2"
  ),

  river_name  = c(
    "Carrera_Ref",  "Carrera_Ref",  "Carrera_Ref",
    "Carrera_Imp1", "Carrera_Imp1", "Carrera_Imp1",
    "Carrera_Imp2", "Carrera_Imp2", "Carrera_Imp2",
    "coyalt_REF",   "coyalt_REF",   "coyalt_REF",
    "coyalt_Imp1",  "coyalt_Imp1",  "coyalt_Imp1",
    "coyalt_Imp2",  "coyalt_Imp2",  "coyalt_Imp2"
  ),

  param       = c(
    "ALK",  "dSi",  "P-PO4",
    "ALK",  "dSi",  "P-PO4",
    "ALK",  "dSi",  "P-PO4",
    "ALK",  "dSi",  "P-PO4",
    "ALK",  "dSi",  "P-PO4",
    "ALK",  "dSi",  "P-PO4"
  ),

  flow_col    = c(
    "Carrera_Ref",  "Carrera_Ref",  "Coyhaique_Ref",
    "Carrera_Imp1", "Carrera_Imp1", "Coyhaique_Imp1",
    "Carrera_Imp2", "Carrera_Imp2", "Coyhaique_Imp2",
    "Coyhaique_Ref","Coyhaique_Ref","Coyhaique_Ref",
    "Coyhaique_Imp1","Coyhaique_Imp1","Coyhaique_Imp1",
    "Coyhaique_Imp2","Coyhaique_Imp2","Coyhaique_Imp2"
  ),

  # Nombres de archivo dentro de param/ (ajusta si los tuyos difieren)
  info_file   = c(
    "Carr_ref_INFO_ALK.csv",   "carr_ref_info_dSi.csv",   "Coyalt_INFO_P-PO4.csv",
    "Carr1_INFO_ALK.csv",      "carr1_info_dSi.csv",      "Carr1_INFO_P-PO4.csv",
    "Carr2_INFO_ALK.csv",      "carr2_info_dSi.csv",      "Carr2_INFO_P-PO4.csv",
    "CoyREF_INFO_ALK.csv",     "CoyREF_info_dSi.csv",     "Coyalt_INFO_P-PO4.csv",
    "CoyAlt1_INFO_ALK.csv",    "CoyAlt1_info_dSi.csv",    "CoyAlt1_INFO_P-PO4.csv",
    "CoyAlt2_INFO_ALK.csv",    "CoyAlt2_info_dSi.csv",    "CoyAlt2_INFO_P-PO4.csv"
  ),

  sample_file = c(
    "Carr_ref_WRTDS_ALK.csv",  "Carr2_WRTDS_dSi.csv",     "CoyREF_WRTDS_PPO4.csv",
    "Carr1_WRTDS_ALK.csv",     "Carr1_WRTDS_dSi.csv",     "Carr1_WRTDS_PPO4.csv",
    "Carr2_WRTDS_ALK.csv",     "Carr2_WRTDS_dSi.csv",     "Carr2_WRTDS_PPO4.csv",
    "CoyREF_WRTDS_ALK.csv",    "CoyREF_WRTDS_dSi.csv",    "CoyREF_WRTDS_PPO4.csv",
    "CoyAlt1_WRTDS_ALK.csv",   "CoyAlt1_WRTDS_dSi.csv",   "CoyAlt1_WRTDS_PPO4.csv",
    "CoyAlt2_WRTDS_ALK.csv",   "CoyAlt2_WRTDS_dSi.csv",   "CoyAlt2_WRTDS_PPO4.csv"
  ),

  daily_file  = rep("Q_compilado.csv", 18),

  model_type  = c(
    "simple", "simple", "grid_search",
    "simple", "simple", "grid_search",
    "simple", "simple", "grid_search",
    "simple", "simple", "grid_search",
    "simple", "simple", "grid_search",
    "simple", "simple", "grid_search"
  )
)

# ------------------------------------------------------------------------------
# [C] PARÁMETROS DE MODELO POR PARÁMETRO QUÍMICO
#     model_type = "simple"  (ALK y dSi usan estos valores directamente)
#     model_type = "grid_search"  (P-PO4 usa su propio grid; los de aquí son ignorados)
# ------------------------------------------------------------------------------
model_params <- list(

  ALK = list(
    divisor    = 1,          # factor de escala sobre la concentración cruda
    windowY    = 8,
    windowQ    = 2,
    windowS    = 0.75,
    minNumObs  = 10,
    minNumUncen = 5,         # se ajusta automáticamente si hay pocas muestras
    use_kalman  = TRUE,
    rho_kalman  = 0.95,
    niter_kalman = 200,
    seed_kalman  = NA,
    info_delim   = ";"       # delimitador del archivo INFO
  ),

  dSi = list(
    divisor    = 0.06008,    # µM -> mg/L  (pon 1 si ya viene en mg/L)
    windowY    = 4,
    windowQ    = 3.1,
    windowS    = 0.38,
    minNumObs  = 6,
    minNumUncen = 5,
    use_kalman  = TRUE,
    rho_kalman  = 0.9,
    niter_kalman = 200,
    seed_kalman  = 123,
    info_delim   = ";"
  ),

  `P-PO4` = list(
    conc_factor  = 1/1000,   # ug/L -> mg/L
    use_kalman   = TRUE,
    rho_kalman   = 0.60,
    niter_kalman = 300,
    seed_kalman  = 1234,
    winsorize_Q  = TRUE,
    Q_lo_prob    = 0.05,
    Q_hi_prob    = 0.95,
    tail_prob    = 0.90,
    tail_weight  = 3,
    spike_allow_ratio  = 1.20,
    spike_severe_ratio = 1.50,
    spike_day_ratio    = 1.10,
    w_max    = 0.35,
    w_nhi    = 0.03,
    w_p995   = 0.15,
    p99_multiplier = 2.2,
    info_delim = ","
  )
)

# ------------------------------------------------------------------------------
# [D] OPCIONES GENERALES
# ------------------------------------------------------------------------------
SKIP_EXISTING  <- FALSE   # TRUE = salta cuencas que ya tienen carpeta de resultados
VERBOSE_MODEL  <- TRUE    # TRUE = muestra progreso del modelEstimation
SAVE_RDS       <- TRUE    # TRUE = guarda objeto EGRET como .rds además del .csv
