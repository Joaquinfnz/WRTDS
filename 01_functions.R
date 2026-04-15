# ==============================================================================
#  01_functions.R  — Funciones compartidas para el pipeline WRTDS
#  No editar a menos que quieras cambiar la lógica del modelo.
# ==============================================================================

# ------------------------------------------------------------------------------
# prepare_daily()
#   Toma el data.frame crudo de Q y devuelve un Daily listo para EGRET.
# ------------------------------------------------------------------------------
prepare_daily <- function(daily_raw, flow_col) {

  if (!("Date" %in% names(daily_raw)))
    stop("Q_compilado.csv no tiene columna 'Date'.")
  if (!(flow_col %in% names(daily_raw)))
    stop(glue("Q_compilado.csv no tiene la columna '{flow_col}'.
              Columnas disponibles: {paste(names(daily_raw), collapse=', ')}"))

  daily <- daily_raw %>%
    transmute(
      Date = as.Date(Date),
      Q    = as.numeric(.data[[flow_col]])
    ) %>%
    arrange(Date)

  daily$Q[daily$Q <= 0] <- NA_real_

  daily <- daily %>% arrange(Date)
  daily$LogQ    <- log(daily$Q)
  daily$DecYear <- as.numeric(lubridate::decimal_date(daily$Date))
  daily$Julian  <- lubridate::yday(daily$Date)
  daily$Month   <- lubridate::month(daily$Date)
  daily$Day     <- lubridate::day(daily$Date)
  daily$MonthSeq <- (daily$DecYear - min(daily$DecYear, na.rm = TRUE)) * 12 + daily$Month

  needed <- c("Date","Q","LogQ","DecYear","Julian","Month","Day","MonthSeq")
  miss   <- setdiff(needed, names(daily))
  if (length(miss) > 0)
    stop(paste("Daily quedó sin columnas EGRET:", paste(miss, collapse=", ")))
  if (!is.finite(min(daily$DecYear, na.rm=TRUE)))
    stop("Daily$DecYear no es finito. Revisa las fechas.")

  message(glue("  Daily: n={nrow(daily)} | NA(Q)={sum(is.na(daily$Q))} | ",
               "%NA(Q)={round(mean(is.na(daily$Q))*100,2)}"))

  return(daily)
}

# ------------------------------------------------------------------------------
# prepare_sample_generic()
#   Parsing robusto de la columna de concentración (coma → punto, etc.).
#   Devuelve Sample con ConcLow/ConcHigh/ConcAve/Uncen listos para EGRET.
#
#   Argumentos:
#     sample_raw  : data.frame leído del CSV de muestras
#     conc_col    : nombre de la columna de concentración en sample_raw
#     divisor     : factor de escala (e.g. 0.06008 para µM→mg/L, 1/1000 para µg/L→mg/L)
#     daily       : data.frame Daily (para filtrar por rango de fechas)
# ------------------------------------------------------------------------------
prepare_sample_generic <- function(sample_raw, conc_col, divisor = 1, daily) {

  if (!(conc_col %in% names(sample_raw)))
    stop(glue("El archivo de muestras no tiene la columna '{conc_col}'.
              Columnas disponibles: {paste(names(sample_raw), collapse=', ')}"))

  s <- sample_raw %>%
    mutate(Date = as.Date(Date)) %>%
    filter(!is.na(Date))

  # Parsing robusto (coma decimal → punto)
  raw_txt <- as.character(s[[conc_col]])
  raw_txt <- stringr::str_replace_all(raw_txt, "\\s+", "")
  raw_txt <- gsub(",", ".", raw_txt)
  conc_clean <- suppressWarnings(as.numeric(raw_txt)) * divisor

  if (all(is.na(conc_clean)))
    stop(glue("La columna '{conc_col}' quedó toda NA. Revisa el formato del CSV."))

  s$conc_clean <- conc_clean
  s$ConcLow    <- conc_clean
  s$ConcHigh   <- conc_clean
  s$ConcAve    <- conc_clean
  s$Uncen      <- 1L

  # Duplicados: promediar por día
  dup_n <- sum(duplicated(s$Date))
  if (dup_n > 0) {
    message(glue("  Aviso: {dup_n} fecha(s) duplicada(s) — consolidando por promedio diario."))
    s <- s %>%
      group_by(Date) %>%
      summarize(
        ConcAve  = mean(ConcAve,  na.rm = TRUE),
        ConcLow  = mean(ConcLow,  na.rm = TRUE),
        ConcHigh = mean(ConcHigh, na.rm = TRUE),
        Uncen    = max(Uncen,     na.rm = TRUE),
        conc_clean = mean(conc_clean, na.rm = TRUE),
        .groups = "drop"
      )
  }

  # Filtrar al rango del Daily
  s <- s %>%
    filter(Date >= min(daily$Date, na.rm = TRUE),
           Date <= max(daily$Date, na.rm = TRUE))

  if (nrow(s) == 0)
    stop("Sample quedó vacío tras filtrar por rango de fechas de Daily.")

  # Columnas EGRET
  s$dateTime <- as.POSIXct(s$Date, format = "%Y-%m-%d", tz = "UTC")
  s <- EGRET::populateSampleColumns(s)
  s$Date <- as.Date(s$dateTime)

  # LogQ desde Daily (match por fecha)
  q_match    <- daily$Q[match(s$Date, daily$Date)]
  s$LogQ     <- NA_real_
  ok_q       <- !is.na(q_match) & q_match > 0
  s$LogQ[ok_q] <- log(q_match[ok_q])

  # Solo fechas presentes en Daily
  s <- s %>% filter(Date %in% daily$Date)

  if (nrow(s) == 0)
    stop("Sample quedó vacío al hacer match exacto con fechas de Daily.")

  message(glue("  Sample final: n={nrow(s)} | NA(conc_clean)={sum(is.na(s$conc_clean))}"))
  return(s)
}

# ------------------------------------------------------------------------------
# winsorize_daily()
#   Aplica winsorización a Daily$Q usando el soporte observado en Sample.
# ------------------------------------------------------------------------------
winsorize_daily <- function(daily, sample, Q_lo_prob = 0.05, Q_hi_prob = 0.95) {
  Q_obs <- daily$Q[match(sample$Date, daily$Date)]
  Q_lo  <- as.numeric(quantile(Q_obs, Q_lo_prob, na.rm = TRUE))
  Q_hi  <- as.numeric(quantile(Q_obs, Q_hi_prob, na.rm = TRUE))

  daily$Q_raw <- daily$Q
  daily$Q     <- pmin(pmax(daily$Q, Q_lo), Q_hi)
  daily$LogQ  <- log(daily$Q)

  message(glue("  Winsorización Q: p{round(Q_lo_prob*100)}={signif(Q_lo,4)} | ",
               "p{round(Q_hi_prob*100)}={signif(Q_hi,4)}"))
  return(daily)
}

# ------------------------------------------------------------------------------
# run_wrtds_simple()
#   Ajusta modelEstimation + (opcional) WRTDSKalman con parámetros fijos.
# ------------------------------------------------------------------------------
run_wrtds_simple <- function(egret_obj, mp, verbose = TRUE) {

  n_uncen  <- sum(egret_obj$Sample$Uncen == 1, na.rm = TRUE)
  min_unc  <- min(mp$minNumUncen, n_uncen)

  egret_obj <- modelEstimation(
    egret_obj,
    minNumObs   = mp$minNumObs,
    minNumUncen = min_unc,
    windowY     = mp$windowY,
    windowQ     = mp$windowQ,
    windowS     = mp$windowS,
    verbose     = verbose
  )

  if (isTRUE(mp$use_kalman)) {
    message("  Aplicando WRTDSKalman...")
    egret_obj <- WRTDSKalman(
      egret_obj,
      rho     = mp$rho_kalman,
      niter   = mp$niter_kalman,
      seed    = mp$seed_kalman,
      verbose = verbose
    )
  }

  return(egret_obj)
}

# ------------------------------------------------------------------------------
# run_wrtds_grid()
#   Pipeline completo con grid search + diagnóstico de spikes + Kalman opcional.
#   Equivale a la lógica de P-PO4.R pero parametrizada.
# ------------------------------------------------------------------------------
run_wrtds_grid <- function(egret_obj, mp, verbose = TRUE) {

  n_total <- nrow(egret_obj$Sample)
  n_uncen <- sum(egret_obj$Sample$Uncen == 1, na.rm = TRUE)

  minObs_safe <- max(25, min(80, floor(0.70 * n_total)))
  minObs_safe <- min(minObs_safe, n_total - 1)
  minUnc_safe <- max(8,  min(12, floor(0.70 * n_uncen)))
  minUnc_safe <- min(minUnc_safe, n_uncen - 1)

  message(sprintf("  minNumObs=%d  minNumUncen=%d  (n=%d, n_uncen=%d)",
                  minObs_safe, minUnc_safe, n_total, n_uncen))

  # Grid de ventanas
  grid <- tribble(
    ~windowY, ~windowQ, ~windowS, ~minObs,                      ~minUnc,
    3.4,      2.6,      0.65,     minObs_safe,                  minUnc_safe,
    3.6,      2.8,      0.70,     max(26, minObs_safe),         max(10, minUnc_safe),
    3.8,      3.0,      0.75,     max(28, minObs_safe),         max(10, minUnc_safe),
    4.0,      3.2,      0.80,     max(30, minObs_safe),         max(10, minUnc_safe),
    3.6,      2.8,      0.85,     max(28, minObs_safe),         max(10, minUnc_safe),
    4.2,      3.2,      0.90,     max(30, minObs_safe),         max(10, minUnc_safe)
  )

  obs_max  <- max(egret_obj$Sample$ConcAve, na.rm = TRUE)
  obs_p99  <- as.numeric(quantile(egret_obj$Sample$ConcAve, 0.99, na.rm = TRUE))
  p99_lim  <- mp$p99_multiplier * obs_p99

  # Función de ajuste interno
  fit_one <- function(windowY, windowQ, windowS, minObs, minUnc) {
    modelEstimation(egret_obj,
                    windowY=windowY, windowQ=windowQ, windowS=windowS,
                    minNumObs=minObs, minNumUncen=minUnc,
                    edgeAdjust=TRUE, verbose=FALSE)
  }

  # Scoring
  score_one <- function(obj) {
    df <- obj$Sample %>%
      select(Date, Obs = ConcAve) %>%
      left_join(obj$Daily %>% select(Date, Mod = ConcDay), by = "Date") %>%
      filter(!is.na(Obs), !is.na(Mod), Obs > 0, Mod > 0)

    thr <- as.numeric(quantile(df$Obs, mp$tail_prob, na.rm = TRUE))
    w   <- ifelse(df$Obs >= thr, mp$tail_weight, 1)
    rmse_log_w <- if (nrow(df) >= 5)
      sqrt(sum(w * (log(df$Mod) - log(df$Obs))^2) / sum(w)) else NA_real_
    bias_log   <- if (nrow(df) >= 5) mean(log(df$Mod) - log(df$Obs)) else NA_real_

    tibble(
      rmse_log_w  = rmse_log_w,
      bias_log    = bias_log,
      maxConcDay  = max(obj$Daily$ConcDay, na.rm = TRUE),
      p99ConcDay  = as.numeric(quantile(obj$Daily$ConcDay, 0.99,  na.rm = TRUE)),
      p995ConcDay = as.numeric(quantile(obj$Daily$ConcDay, 0.995, na.rm = TRUE))
    )
  }

  # Evaluar grid
  fit_table <- purrr::pmap_dfr(grid, function(windowY, windowQ, windowS, minObs, minUnc) {
    obj <- fit_one(windowY, windowQ, windowS, minObs, minUnc)
    sc  <- score_one(obj)
    tibble(windowY, windowQ, windowS, minObs, minUnc) %>% bind_cols(sc)
  })

  fit_table <- fit_table %>%
    mutate(
      spike_ratio_max  = maxConcDay / obs_max,
      spike_ratio_p995 = p995ConcDay / obs_max,
      pen_max   = pmax(0, spike_ratio_max  - mp$spike_allow_ratio),
      pen_p995  = pmax(0, spike_ratio_p995 - mp$spike_allow_ratio),
      pass_p99  = (p99ConcDay <= p99_lim),
      objective = rmse_log_w + mp$w_max * pen_max + mp$w_p995 * pen_p995
    )

  candidates <- if (any(fit_table$pass_p99, na.rm = TRUE)) {
    message(glue("  Filtro p99 activo: usando filas con p99ConcDay <= {round(p99_lim,5)}"))
    fit_table %>% filter(pass_p99)
  } else {
    warning("  Ninguna fila pasó filtro p99 — seleccionando por objetivo penalizado.")
    fit_table
  }

  best <- candidates %>% arrange(objective) %>% slice(1)
  message(glue("  Seleccionado: windowY={best$windowY}, windowQ={best$windowQ}, ",
               "windowS={best$windowS}  |  rmse_log_w={round(best$rmse_log_w,5)} ",
               "|  spike_ratio={round(best$spike_ratio_max,2)}x"))

  # Ajuste con el mejor set
  EGRET_base <- fit_one(best$windowY, best$windowQ, best$windowS, best$minObs, best$minUnc)

  # Fallback ULTRA-SMOOTH si hay spike severo
  spike_ratio <- max(EGRET_base$Daily$ConcDay, na.rm = TRUE) / obs_max
  if (is.finite(spike_ratio) && spike_ratio > mp$spike_severe_ratio) {
    warning(glue("  Spike severo ({round(spike_ratio,2)}x) → re-ajustando con ULTRA-SMOOTH."))
    EGRET_base <- modelEstimation(
      egret_obj,
      windowY=4.5, windowQ=3.5, windowS=1.00,
      minNumObs=max(best$minObs,30), minNumUncen=max(best$minUnc,10),
      edgeAdjust=TRUE, verbose=verbose
    )
    spike_ratio <- max(EGRET_base$Daily$ConcDay, na.rm = TRUE) / obs_max
  }

  # Kalman (solo si el spike es aceptable)
  if (isTRUE(mp$use_kalman) && is.finite(spike_ratio) && spike_ratio <= mp$spike_allow_ratio) {
    message(glue("  Aplicando Kalman (rho={mp$rho_kalman})."))
    EGRET_base <- WRTDSKalman(
      EGRET_base,
      rho=mp$rho_kalman, niter=mp$niter_kalman,
      seed=mp$seed_kalman, verbose=verbose
    )
  } else {
    message(glue("  Kalman NO aplicado (spike_ratio={round(spike_ratio,2)}, umbral={mp$spike_allow_ratio})."))
  }

  return(EGRET_base)
}

# ------------------------------------------------------------------------------
# make_plot_obs_vs_model()
#   Gráfico observado vs modelado (desde primera muestra).
# ------------------------------------------------------------------------------
make_plot_obs_vs_model <- function(results, sample, param, river_name,
                                   conc_col = "conc_clean") {

  results <- results %>% mutate(Date = as.Date(Date))
  sample  <- sample  %>% arrange(Date)

  date_min <- min(sample$Date[!is.na(sample[[conc_col]])], na.rm = TRUE)

  res_plot <- results %>% filter(Date >= date_min)
  smp_plot <- sample  %>% filter(Date >= date_min)

  ggplot() +
    geom_line(
      data = res_plot,
      aes(x = Date, y = ConcDay, color = "Modelo WRTDS"),
      linewidth = 1
    ) +
    geom_point(
      data = smp_plot,
      aes(x = Date, y = .data[[conc_col]], color = "Datos Observados"),
      size = 2, alpha = 0.8
    ) +
    labs(
      title = glue("Observado vs. Modelado — {param} | {river_name}"),
      x     = "Fecha",
      y     = "Concentración",
      color = NULL
    ) +
    scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
    scale_color_manual(
      values = c("Datos Observados" = "red", "Modelo WRTDS" = "#0073C2FF")
    ) +
    theme_minimal() +
    theme(
      plot.title    = element_text(size = 13, face = "bold", hjust = 0.5),
      axis.title    = element_text(size = 11, face = "bold"),
      axis.text     = element_text(size = 9),
      panel.grid.major = element_line(color = "gray85", linetype = "dashed"),
      panel.grid.minor = element_blank(),
      legend.position  = "bottom"
    )
}
