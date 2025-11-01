WITH
  -- 1. Identify and rank ICU stays to find the first one per admission
  icustays_ranked AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.hadm_id,
      a.hospital_expire_flag,
      i.stay_id,
      i.intime,
      i.outtime,
      i.los,
      DENSE_RANK() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS stay_rank
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON a.hadm_id = i.hadm_id
  ),
  -- 2. Filter for the first ICU stay, capturing demographics and outcomes
  icustay_details AS (
    SELECT
      subject_id,
      gender,
      anchor_age,
      hadm_id,
      hospital_expire_flag,
      stay_id,
      intime,
      outtime,
      los,
      -- Flag for our primary cohort of interest
      (gender = 'M' AND anchor_age BETWEEN 40 AND 50) AS is_male_40_50
    FROM icustays_ranked
    WHERE
      stay_rank = 1
  ),
  -- 3. Identify hospital admissions with a respiratory failure diagnosis
  respiratory_failure_hadm AS (
    SELECT DISTINCT
      hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND icd_code IN ('51881', '51882', '51884')) -- Acute/chronic resp failure
      OR (icd_version = 10 AND STARTS_WITH(icd_code, 'J96')) -- Respiratory failure
  ),
  -- 4. Create the final cohort of respiratory failure patients in their first ICU stay
  cohort AS (
    SELECT
      icd.*
    FROM icustay_details AS icd
    INNER JOIN respiratory_failure_hadm AS rfh
      ON icd.hadm_id = rfh.hadm_id
  ),
  -- 5. Extract relevant vital signs from the first 48 hours of the ICU stay for the cohort
  vitals_raw AS (
    SELECT
      c.stay_id,
      ce.charttime,
      ce.itemid,
      ce.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN cohort AS c
      ON ce.stay_id = c.stay_id
    WHERE
      ce.itemid IN (
        220045, -- Heart Rate
        220210, 224690, -- Respiratory Rate
        220277, -- O2 saturation pulseoxymetry
        220052, 220181, 225312 -- MAP (Invasive and Non-invasive)
      )
      AND ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  ),
  -- 6. Calculate time-weighted burdens for hypotension and tachycardia
  burden_per_stay AS (
    SELECT
      stay_id,
      -- Hypotensive burden: time MAP < 65 / total time with MAP measurements
      SAFE_DIVIDE(
        SUM(
          CASE
            WHEN itemid IN (220052, 220181, 225312) AND valuenum < 65
              THEN TIMESTAMP_DIFF(next_charttime, charttime, MINUTE)
            ELSE 0
          END
        ),
        SUM(
          CASE
            WHEN itemid IN (220052, 220181, 225312)
              THEN TIMESTAMP_DIFF(next_charttime, charttime, MINUTE)
            ELSE NULL
          END
        )
      ) AS hypotensive_burden,
      -- Tachycardic burden: time HR > 100 / total time with HR measurements
      SAFE_DIVIDE(
        SUM(
          CASE
            WHEN itemid = 220045 AND valuenum > 100
              THEN TIMESTAMP_DIFF(next_charttime, charttime, MINUTE)
            ELSE 0
          END
        ),
        SUM(
          CASE
            WHEN itemid = 220045
              THEN TIMESTAMP_DIFF(next_charttime, charttime, MINUTE)
            ELSE NULL
          END
        )
      ) AS tachycardic_burden
    FROM (
      SELECT
        stay_id,
        charttime,
        itemid,
        valuenum,
        LEAD(charttime, 1) OVER (PARTITION BY stay_id, itemid ORDER BY charttime) AS next_charttime
      FROM vitals_raw
      WHERE
        itemid IN (220045, 220052, 220181, 225312) -- Vitals for burden calculation
    )
    WHERE
      next_charttime IS NOT NULL
    GROUP BY
      stay_id
  ),
  -- 7. Calculate Vital Instability Index (VII)
  vii_per_stay AS (
    SELECT
      stay_id,
      SUM(avg_score) AS vital_instability_index
    FROM (
      SELECT
        stay_id,
        vital_category,
        AVG(score) AS avg_score
      FROM (
        SELECT
          stay_id,
          valuenum,
          -- Categorize vitals
          CASE
            WHEN itemid = 220045 THEN 'hr'
            WHEN itemid IN (220210, 224690) THEN 'rr'
            WHEN itemid = 220277 THEN 'spo2'
            WHEN itemid IN (220052, 220181, 225312) THEN 'map'
          END AS vital_category,
          -- Assign score based on abnormality
          CASE
            WHEN itemid = 220045 -- Heart Rate
              THEN CASE WHEN valuenum > 130 THEN 3 WHEN valuenum > 110 THEN 2 WHEN valuenum > 100 THEN 1 WHEN valuenum >= 50 THEN 0 WHEN valuenum >= 40 THEN 1 ELSE 2 END
            WHEN itemid IN (220210, 224690) -- Respiratory Rate
              THEN CASE WHEN valuenum > 30 THEN 3 WHEN valuenum > 25 THEN 2 WHEN valuenum > 20 THEN 1 WHEN valuenum >= 12 THEN 0 WHEN valuenum >= 9 THEN 1 WHEN valuenum >= 6 THEN 2 ELSE 3 END
            WHEN itemid = 220277 -- SpO2
              THEN CASE WHEN valuenum >= 95 THEN 0 WHEN valuenum >= 90 THEN 1 WHEN valuenum >= 85 THEN 2 ELSE 3 END
            WHEN itemid IN (220052, 220181, 225312) -- MAP
              THEN CASE WHEN valuenum > 110 THEN 2 WHEN valuenum > 100 THEN 1 WHEN valuenum >= 65 THEN 0 WHEN valuenum >= 60 THEN 1 WHEN valuenum >= 50 THEN 2 ELSE 3 END
          END AS score
        FROM vitals_raw
      )
      WHERE
        score IS NOT NULL
      GROUP BY
        stay_id, vital_category
    )
    GROUP BY
      stay_id
  ),
  -- 8. Combine all metrics at the patient-stay level
  patient_level_metrics AS (
    SELECT
      c.stay_id,
      c.is_male_40_50,
      c.los AS icu_los,
      c.hospital_expire_flag,
      b.hypotensive_burden,
      b.tachycardic_burden,
      v.vital_instability_index
    FROM cohort AS c
    LEFT JOIN burden_per_stay AS b
      ON c.stay_id = b.stay_id
    LEFT JOIN vii_per_stay AS v
      ON c.stay_id = v.stay_id
  )
-- 9. Final aggregation and presentation for the two groups
-- Group A: Male, 40-50, with Respiratory Failure
SELECT
  'Male 40-50 with RF' AS cohort_group,
  COUNT(DISTINCT stay_id) AS patient_count,
  AVG(icu_los) AS avg_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
  AVG(hypotensive_burden) * 100 AS avg_hypotensive_burden_percent,
  AVG(tachycardic_burden) * 100 AS avg_tachycardic_burden_percent,
  STDDEV(vital_instability_index) AS vii_stddev,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(25)] AS vii_p25,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(50)] AS vii_p50,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(75)] AS vii_p75,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(95)] AS vii_p95
FROM patient_level_metrics
WHERE
  is_male_40_50
UNION ALL
-- Group B: All patients with Respiratory Failure
SELECT
  'All with RF' AS cohort_group,
  COUNT(DISTINCT stay_id) AS patient_count,
  AVG(icu_los) AS avg_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
  AVG(hypotensive_burden) * 100 AS avg_hypotensive_burden_percent,
  AVG(tachycardic_burden) * 100 AS avg_tachycardic_burden_percent,
  STDDEV(vital_instability_index) AS vii_stddev,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(25)] AS vii_p25,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(50)] AS vii_p50,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(75)] AS vii_p75,
  APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(95)] AS vii_p95
FROM patient_level_metrics;