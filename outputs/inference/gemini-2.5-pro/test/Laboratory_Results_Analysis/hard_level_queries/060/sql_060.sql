WITH
  -- Step 1: Identify hospital admissions for the Post-Cardiac Arrest (PCA) cohort
  cohort_pca_hadm_ids AS (
    SELECT DISTINCT adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
      ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 52 AND 62
      AND LOWER(ddx.long_title) LIKE '%cardiac arrest%'
  ),

  -- Step 2: Calculate the instability score for each ICU stay in the PCA cohort
  instability_scores_per_stay AS (
    SELECT
      icu.stay_id,
      -- Define and count abnormal vital signs in the first 48 hours of the ICU stay
      COUNTIF(
        (ce.itemid = 220045 AND (ce.valuenum < 60 OR ce.valuenum > 100)) -- Heart Rate
        OR (ce.itemid IN (220179, 220050) AND (ce.valuenum < 90 OR ce.valuenum > 140)) -- Systolic BP
        OR (ce.itemid IN (220181, 220052) AND ce.valuenum < 65) -- Mean Arterial Pressure
        OR (ce.itemid = 220210 AND (ce.valuenum < 12 OR ce.valuenum > 20)) -- Respiratory Rate
        OR (ce.itemid = 220277 AND ce.valuenum < 90) -- SpO2
        OR (ce.itemid = 223762 AND (ce.valuenum < 36 OR ce.valuenum > 38.3)) -- Temperature C
        OR (ce.itemid = 223761 AND ((ce.valuenum - 32) * 5.0 / 9.0 < 36 OR (ce.valuenum - 32) * 5.0 / 9.0 > 38.3)) -- Temperature F (corrected conversion to C)
      ) AS instability_score
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN cohort_pca_hadm_ids
      ON icu.hadm_id = cohort_pca_hadm_ids.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON icu.stay_id = ce.stay_id
    WHERE
      -- Filter for events within the first 48 hours of ICU admission
      ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
      AND ce.valuenum IS NOT NULL
    GROUP BY
      icu.stay_id
  ),

  -- Step 3: Calculate quartiles and IQR for the instability score
  instability_stats_cte AS (
    SELECT
      quantiles[OFFSET(1)] AS instability_score_q1,
      quantiles[OFFSET(2)] AS instability_score_median,
      quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS instability_score_iqr
    FROM (
      SELECT APPROX_QUANTILES(instability_score, 4) AS quantiles
      FROM instability_scores_per_stay
    )
  ),

  -- Step 4: Pre-calculate the number of critical lab events per admission for all patients
  lab_counts AS (
    SELECT
      hadm_id,
      COUNT(*) AS num_critical_labs
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
      flag = 'abnormal'
    GROUP BY
      hadm_id
  ),

  -- Step 5: Calculate comparison metrics for the PCA cohort
  pca_metrics_cte AS (
    SELECT
      AVG(lc.num_critical_labs) AS avg_critical_labs,
      AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS avg_los_days,
      AVG(adm.hospital_expire_flag) * 100 AS mortality_rate_percent
    FROM cohort_pca_hadm_ids AS pca
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pca.hadm_id = adm.hadm_id
    LEFT JOIN lab_counts AS lc
      ON pca.hadm_id = lc.hadm_id
  ),

  -- Step 6: Calculate comparison metrics for the general inpatient population
  general_metrics_cte AS (
    SELECT
      AVG(lc.num_critical_labs) AS avg_critical_labs,
      AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS avg_los_days,
      AVG(adm.hospital_expire_flag) * 100 AS mortality_rate_percent
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    LEFT JOIN lab_counts AS lc
      ON adm.hadm_id = lc.hadm_id
  )

-- Final Step: Combine all results into a single, wide row for easy comparison
SELECT
  -- Instability Score statistics for the PCA cohort
  instability.instability_score_q1,
  instability.instability_score_median,
  instability.instability_score_iqr,

  -- Comparative metrics: PCA vs. General
  pca.avg_critical_labs AS avg_critical_labs_pca_cohort,
  general.avg_critical_labs AS avg_critical_labs_general_inpatients,
  pca.avg_los_days AS avg_los_days_pca_cohort,
  general.avg_los_days AS avg_los_days_general_inpatients,
  pca.mortality_rate_percent AS mortality_rate_percent_pca_cohort,
  general.mortality_rate_percent AS mortality_rate_percent_general_inpatients
FROM
  instability_stats_cte AS instability,
  pca_metrics_cte AS pca,
  general_metrics_cte AS general;