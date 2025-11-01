WITH
  -- HFNC itemids from ICU items
  hfnc_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE LOWER(label) LIKE '%high flow%' OR LOWER(label) LIKE '%hfnc%'
  ),
  -- Heart rate itemids
  hr_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%hr%'
  ),
  -- Systolic BP itemids
  sbp_itemids AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE LOWER(label) LIKE '%systolic%' OR LOWER(label) LIKE '%blood pressure systolic%' OR LOWER(label) LIKE '%bp systolic%'
  ),
  -- Base population: male ICU patients aged 55-65
  base_patients AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      i.los AS icu_los_hours,
      a.hospital_expire_flag,
      a.deathtime,
      p.anchor_age,
      p.gender
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON i.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'Male'
      AND p.anchor_age BETWEEN 55 AND 65
  ),
  -- Per-patient metrics
  per_patient AS (
    SELECT
      bp.subject_id,
      bp.hadm_id,
      bp.stay_id,
      bp.intime,
      bp.outtime,
      bp.icu_los_hours,
      bp.hospital_expire_flag,
      bp.deathtime,
      bp.anchor_age,
      bp.gender,
      -- cohort: HFNC within 24h or Control
      CASE
        WHEN EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
          WHERE ie.subject_id = bp.subject_id
            AND ie.hadm_id = bp.hadm_id
            AND ie.stay_id = bp.stay_id
            AND ie.starttime >= bp.intime
            AND ie.starttime < TIMESTAMP_ADD(bp.intime, INTERVAL 24 HOUR)
            AND ie.itemid IN (SELECT itemid FROM hfnc_itemids)
        ) THEN 'HFNC_24h'
        ELSE 'Control'
      END AS cohort_label,
      -- tachycardia burden within first 24h
      (
        SELECT COUNT(*)
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
        WHERE ce.subject_id = bp.subject_id
          AND ce.hadm_id = bp.hadm_id
          AND ce.stay_id = bp.stay_id
          AND ce.charttime >= bp.intime
          AND ce.charttime < TIMESTAMP_ADD(bp.intime, INTERVAL 24 HOUR)
          AND ce.itemid IN (SELECT itemid FROM hr_itemids)
          AND ce.valuenum > 100
      ) AS tachyburden,
      -- hypotension burden within first 24h
      (
        SELECT COUNT(*)
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
        WHERE ce.subject_id = bp.subject_id
          AND ce.hadm_id = bp.hadm_id
          AND ce.stay_id = bp.stay_id
          AND ce.charttime >= bp.intime
          AND ce.charttime < TIMESTAMP_ADD(bp.intime, INTERVAL 24 HOUR)
          AND ce.itemid IN (SELECT itemid FROM sbp_itemids)
          AND ce.valuenum <= 90
      ) AS hypotburden,
      -- instability score = tachyburden + hypotburden
      (
        (
          SELECT COUNT(*)
          FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
          WHERE ce.subject_id = bp.subject_id
            AND ce.hadm_id = bp.hadm_id
            AND ce.stay_id = bp.stay_id
            AND ce.charttime >= bp.intime
            AND ce.charttime < TIMESTAMP_ADD(bp.intime, INTERVAL 24 HOUR)
            AND ce.itemid IN (SELECT itemid FROM hr_itemids)
            AND ce.valuenum > 100
        ) +
        (
          SELECT COUNT(*)
          FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
          WHERE ce.subject_id = bp.subject_id
            AND ce.hadm_id = bp.hadm_id
            AND ce.stay_id = bp.stay_id
            AND ce.charttime >= bp.intime
            AND ce.charttime < TIMESTAMP_ADD(bp.intime, INTERVAL 24 HOUR)
            AND ce.itemid IN (SELECT itemid FROM sbp_itemids)
            AND ce.valuenum <= 90
        )
      ) AS instability_score,
      -- mortality flag (in-hospital mortality)
      CASE WHEN bp.hospital_expire_flag = 1 OR bp.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality_flag
    FROM base_patients bp
  )
SELECT
  cohort_label AS cohort,
  -- Instability score percentiles
  APPROX_QUANTILES(instability_score, 100)[OFFSET(24)] AS instability_p25,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS instability_p50,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(74)] AS instability_p75,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(94)] AS instability_p95,
  -- Tachycardia burden percentiles
  APPROX_QUANTILES(tachyburden, 100)[OFFSET(24)] AS tachyburden_p25,
  APPROX_QUANTILES(tachyburden, 100)[OFFSET(50)] AS tachyburden_p50,
  APPROX_QUANTILES(tachyburden, 100)[OFFSET(74)] AS tachyburden_p75,
  APPROX_QUANTILES(tachyburden, 100)[OFFSET(94)] AS tachyburden_p95,
  -- Hypotension burden percentiles
  APPROX_QUANTILES(hypotburden, 100)[OFFSET(24)] AS hypotburden_p25,
  APPROX_QUANTILES(hypotburden, 100)[OFFSET(50)] AS hypotburden_p50,
  APPROX_QUANTILES(hypotburden, 100)[OFFSET(74)] AS hypotburden_p75,
  APPROX_QUANTILES(hypotburden, 100)[OFFSET(94)] AS hypotburden_p95,
  -- ICU LOS percentiles (hours)
  APPROX_QUANTILES(icu_los_hours, 100)[OFFSET(24)] AS los_p25,
  APPROX_QUANTILES(icu_los_hours, 100)[OFFSET(50)] AS los_p50,
  APPROX_QUANTILES(icu_los_hours, 100)[OFFSET(74)] AS los_p75,
  APPROX_QUANTILES(icu_los_hours, 100)[OFFSET(94)] AS los_p95,
  -- Mortality rate
  AVG(mortality_flag) AS mortality_rate
FROM per_patient
GROUP BY cohort_label
ORDER BY cohort_label;