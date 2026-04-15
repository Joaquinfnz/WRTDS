# ==============================================================================
#  02_run_all.R  — Script principal. Ejecuta todas las cuencas × parámetros.
#
#  USO:
#    1. Abre RStudio.
#    2. Abre este archivo y haz "Source" (Ctrl+Shift+S / Cmd+Shift+S).
#    3. O desde terminal:  Rscript 02_run_all.R
#
#  ANTES DE CORRER:
#    - Edita BASE_DIR en 00_config.R
#    - Verifica que la tabla `runs` coincide con tus archivos reales
#
#  RESULTADOS:
#    Cada corrida genera una subcarpeta dentro de basin_dir/Results/:
#      {river_name}_{param}_WRTDS/
#        ├── WRTDS_Output_{param}.csv
#        ├── modelResults_{param}.rds   (si SAVE_RDS = TRUE)
#        └── Fig_{param}_obs_vs_model.png
# ==============================================================================

# ── 0. Paquetes ──────────────────────────────────────────────────────────────
if (!("pacman" %in% installed.packages()[, "Package"])) install.packages("pacman")
pacman::p_load(
  tidyverse, stringr, lubridate, reshape2, data.table,
  dataRetrieval, EGRET, EGRETci, readr, glue, purrr, tibble, ggplot2
)

# ── 1. Cargar config y funciones ─────────────────────────────────────────────
# Asume que los tres archivos están en la misma carpeta.
script_dir <- tryCatch(
  dirname(rstudioapi::getSourceEditorContext()$path),   # en RStudio
  error = function(e) getwd()                           # en terminal
)

source(file.path(script_dir, "00_config.R"))
source(file.path(script_dir, "01_functions.R"))

# ── 2. Loop principal ────────────────────────────────────────────────────────
n_runs  <- nrow(runs)
ok_runs <- character(0)
fail_runs <- list()

for (i in seq_len(n_runs)) {

  r <- runs[i, ]
  run_label <- r$run_id

  message("\n", strrep("=", 60))
  message(glue("▶  [{i}/{n_runs}]  {run_label}"))
  message(strrep("=", 60))

  # Construir ruta de trabajo
  work_dir    <- file.path(BASE_DIR, r$basin_dir)
  param_dir   <- file.path(work_dir, r$param)
  output_path <- file.path(work_dir, "Results",
                           glue("{r$river_name}_{r$param}_WRTDS"))

  # ── Saltar si ya existe (opcional) ─────────────────────────────────────────
  if (isTRUE(SKIP_EXISTING) && dir.exists(output_path)) {
    message(glue("  ⏭  Saltando (ya existe): {output_path}"))
    ok_runs <- c(ok_runs, run_label)
    next
  }

  # ── Verificar que existen los archivos de entrada ──────────────────────────
  info_path   <- file.path(param_dir, r$info_file)
  sample_path <- file.path(param_dir, r$sample_file)
  daily_path  <- file.path(param_dir, r$daily_file)

  missing_files <- c(info_path, sample_path, daily_path)[
    !file.exists(c(info_path, sample_path, daily_path))
  ]
  if (length(missing_files) > 0) {
    msg <- glue("  ✘  Archivos no encontrados:\n    {paste(missing_files, collapse='\n    ')}")
    warning(msg)
    fail_runs[[run_label]] <- msg
    next
  }

  # ── Encapsular en tryCatch para que un error no detenga todo ──────────────
  result <- tryCatch({

    mp <- model_params[[r$param]]

    # ── Leer datos ───────────────────────────────────────────────────────────
    INFO      <- read_delim(info_path,   delim = mp$info_delim,
                            escape_double = FALSE, trim_ws = TRUE,
                            show_col_types = FALSE)
    Sample_raw <- read_csv(sample_path,  na = c("", "NA", ","),
                           show_col_types = FALSE)
    Daily_raw  <- read_csv(daily_path,   na = c("", "NA"),
                           show_col_types = FALSE)

    # ── Preparar Daily ───────────────────────────────────────────────────────
    Daily <- prepare_daily(Daily_raw, r$flow_col)

    # ── Preparar Sample según el tipo de parámetro ───────────────────────────
    if (r$param == "ALK") {
      Sample <- prepare_sample_generic(Sample_raw, "ALK", mp$divisor, Daily)

    } else if (r$param == "dSi") {
      INFO$param.units <- "mg/L"
      Sample <- prepare_sample_generic(Sample_raw, "dSi", mp$divisor, Daily)

    } else if (r$param == "P-PO4") {
      # P-PO4 usa columna "Conc" (en µg/L)
      Sample_raw$`P-PO4` <- Sample_raw$Conc * mp$conc_factor
      Sample_raw$ConcLow  <- Sample_raw$`P-PO4`
      Sample_raw$ConcHigh <- Sample_raw$`P-PO4`
      Sample_raw$ConcAve  <- Sample_raw$`P-PO4`
      Sample_raw$Uncen    <- 1L
      # consolidar duplicados
      if (any(duplicated(Sample_raw$Date))) {
        Sample_raw <- Sample_raw %>%
          group_by(Date) %>%
          summarize(
            ConcAve  = mean(ConcAve,  na.rm = TRUE),
            ConcLow  = mean(ConcLow,  na.rm = TRUE),
            ConcHigh = mean(ConcHigh, na.rm = TRUE),
            Uncen    = max(Uncen,     na.rm = TRUE),
            `P-PO4`  = mean(`P-PO4`, na.rm = TRUE),
            .groups  = "drop"
          )
      }
      Sample_raw <- Sample_raw %>%
        mutate(Date = as.Date(Date)) %>%
        filter(!is.na(Date), Date %in% Daily$Date)

      if (nrow(Sample_raw) == 0) stop("Sample quedó vacío tras cruce con Daily.")

      # Winsorización del Q antes de LogQ
      if (isTRUE(mp$winsorize_Q))
        Daily <- winsorize_daily(Daily, Sample_raw, mp$Q_lo_prob, mp$Q_hi_prob)

      Sample_raw$dateTime <- as.POSIXct(Sample_raw$Date, format="%Y-%m-%d", tz="UTC")
      Sample_raw <- EGRET::populateSampleColumns(Sample_raw)
      Sample_raw$Date  <- as.Date(Sample_raw$dateTime)
      Sample_raw$Q     <- Daily$Q[match(Sample_raw$Date, Daily$Date)]
      Sample_raw$LogQ  <- log(Sample_raw$Q)
      Sample_raw$conc_clean <- Sample_raw$ConcAve

      Sample <- Sample_raw %>% filter(Date %in% Daily$Date)
      if (nrow(Sample) == 0) stop("Sample vacío tras match exacto con Daily.")
    }

    # ── Crear objeto EGRET ───────────────────────────────────────────────────
    EGRET_input <- EGRET::mergeReport(INFO, Daily, Sample)

    # ── Ajustar modelo ───────────────────────────────────────────────────────
    if (r$model_type == "simple") {
      EGRET_input <- run_wrtds_simple(EGRET_input, mp, verbose = VERBOSE_MODEL)
    } else {
      EGRET_input <- run_wrtds_grid(EGRET_input, mp, verbose = VERBOSE_MODEL)
    }

    # ── Guardar resultados ───────────────────────────────────────────────────
    dir.create(output_path, showWarnings = FALSE, recursive = TRUE)

    write.csv(EGRET_input$Daily,
              file.path(output_path, glue("WRTDS_Output_{r$param}.csv")),
              row.names = FALSE)

    if (isTRUE(SAVE_RDS))
      saveRDS(EGRET_input,
              file.path(output_path, glue("modelResults_{r$param}.rds")))

    # ── Gráfico ──────────────────────────────────────────────────────────────
    results_df <- read_csv(
      file.path(output_path, glue("WRTDS_Output_{r$param}.csv")),
      show_col_types = FALSE
    )

    p1 <- make_plot_obs_vs_model(
      results    = results_df,
      sample     = Sample,
      param      = r$param,
      river_name = r$river_name,
      conc_col   = "conc_clean"
    )

    ggsave(
      filename = file.path(output_path, glue("Fig_{r$param}_obs_vs_model.png")),
      plot     = p1,
      width    = 11, height = 5.5, dpi = 300
    )

    message(glue("  ✔  Guardado en: {output_path}"))
    "ok"

  }, error = function(e) {
    msg <- conditionMessage(e)
    warning(glue("  ✘  Error en {run_label}: {msg}"))
    msg
  })

  if (identical(result, "ok")) {
    ok_runs <- c(ok_runs, run_label)
  } else {
    fail_runs[[run_label]] <- result
  }
}

# ── 3. Resumen final ─────────────────────────────────────────────────────────
message("\n", strrep("═", 60))
message(glue("RESUMEN: {length(ok_runs)}/{n_runs} corridas exitosas"))
message(strrep("═", 60))

if (length(ok_runs) > 0) {
  message("  ✔  OK:   ", paste(ok_runs, collapse = ", "))
}
if (length(fail_runs) > 0) {
  message("  ✘  FALLO:")
  for (nm in names(fail_runs))
    message(glue("     • {nm}: {fail_runs[[nm]]}"))
}
