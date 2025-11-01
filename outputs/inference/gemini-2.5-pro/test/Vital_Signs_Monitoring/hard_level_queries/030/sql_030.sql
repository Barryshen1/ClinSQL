WITH
  -- Step 1: Identify the specific cohort of ICU stays.
  -- Cohort: 43-53 year old females with a diagnosis of acute respiratory failure.
  cohort_stays AS (
    SELECT DISTINCT
      icu.stay_id,
      icu.hadm_id,
      icu.subject_id,
      icu.intime,
      icu.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON icu.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON icu.hadm_id = dx.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
      ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 43 AND 53
      AND LOWER(ddx.long_title) LIKE '%acute respiratory failure%'
  ),

  -- Step 2: Extract and clean relevant vital signs for the cohort in the first 48 hours.
  cohort_vitals_48h AS (
    SELECT
      cs.stay_id,
      ce.itemid,
      -- Standardize temperature to Celsius
      CASE
        WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5 / 9
        ELSE ce.valuenum
      END AS valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN cohort_stays AS cs
      ON ce.stay_id = cs.stay_id
    WHERE
      ce.charttime BETWEEN cs.intime AND TIMESTAMP_ADD(cs.intime, INTERVAL 48 HOUR)
      AND ce.valuenum IS NOT NULL
      AND ce.itemid IN (
        220045, -- Heart Rate
        220181, -- Arterial Blood Pressure mean
        225312, -- NBP mean
        220210, -- Respiratory Rate
        220277, -- O2 saturation pulseox
        223762, -- Temperature Celsius
        223761  -- Temperature Fahrenheit
      )
  ),

  -- Step 3: Calculate the custom Vital Instability Index (VII) for each patient in the cohort.
  -- The index is the sum of proportions of abnormal measurements for 5 key vitals.
  patient_vii AS (
    SELECT
      stay_id,
      -- Sum of instability ratios for each vital sign
      (
        COALESCE(hr_instability, 0)
        + COALESCE(map_instability, 0)
        + COALESCE(rr_instability, 0)
        + COALESCE(spo2_instability, 0)
        + COALESCE(temp_instability, 0)
      ) AS vital_instability_index
    FROM (
      SELECT
        stay_id,
        SAFE_DIVIDE(
          SUM(CASE WHEN itemid = 220045 AND (valuenum > 100 OR valuenum < 60) THEN 1 ELSE 0 END),
          SUM(CASE WHEN itemid = 220045 THEN 1 ELSE 0 END)
        ) AS hr_instability,
        SAFE_DIVIDE(
          SUM(CASE WHEN itemid IN (220181, 225312) AND valuenum < 65 THEN 1 ELSE 0 END),
          SUM(CASE WHEN itemid IN (220181, 225312) THEN 1 ELSE 0 END)
        ) AS map_instability,
        SAFE_DIVIDE(
          SUM(CASE WHEN itemid = 220210 AND (valuenum > 20 OR valuenum < 12) THEN 1 ELSE 0 END),
          SUM(CASE WHEN itemid = 220210 THEN 1 ELSE 0 END)
        ) AS rr_instability,
        SAFE_DIVIDE(
          SUM(CASE WHEN itemid = 220277 AND valuenum < 92 THEN 1 ELSE 0 END),
          SUM(CASE WHEN itemid = 220277 THEN 1 ELSE 0 END)
        ) AS spo2_instability,
        SAFE_DIVIDE(
          SUM(CASE WHEN itemid IN (223761, 223762) AND (valuenum > 38 OR valuenum < 36) THEN 1 ELSE 0 END),
          SUM(CASE WHEN itemid IN (223761, 223762) THEN 1 ELSE 0 END)
        ) AS temp_instability
      FROM cohort_vitals_48h
      GROUP BY
        stay_id
    )
  ),

  -- Step 4: Calculate the 95th percentile VII for the cohort and the 75th percentile for top quartile cutoff.
  cohort_vii_stats AS (
    SELECT
      APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(95)] AS p95_vii_for_cohort,
      APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(75)] AS p75_vii_cutoff
    FROM patient_vii
  ),

  -- Step 5: Identify the stay_ids belonging to the top quartile of the cohort based on VII.
  top_quartile_stays AS (
    SELECT
      p.stay_id
    FROM patient_vii AS p
    CROSS JOIN cohort_vii_stats AS s
    WHERE
      p.vital_instability_index >= s.p75_vii_cutoff
  ),

  -- Step 6: Get vitals, LOS, and mortality for the entire ICU population to compute comparison metrics.
  population_metrics AS (
    SELECT
      icu.stay_id,
      -- Check if the stay belongs to the top quartile of our cohort
      CASE
        WHEN tqs.stay_id IS NOT NULL THEN 'Top Quartile of Cohort'
        ELSE 'General ICU Population'
      END AS population_group,
      -- Count of hypotension/tachycardia measurements in first 48 hours
      SUM(CASE WHEN ce.itemid IN (220181, 225312) AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_episodes,
      SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_episodes,
      MAX(icu.los) AS icu_los,
      MAX(adm.hospital_expire_flag) AS hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON icu.stay_id = ce.stay_id
      AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
      AND ce.itemid IN (220045, 220181, 225312) AND ce.valuenum IS NOT NULL
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.hadm_id = adm.hadm_id
    LEFT JOIN top_quartile_stays AS tqs
      ON icu.stay_id = tqs.stay_id
    GROUP BY
      icu.stay_id, tqs.stay_id
  ),

  -- Step 7: Aggregate the metrics for the two groups: Top Quartile and General Population.
  final_comparison AS (
    SELECT
      'Top Quartile of Cohort' AS population_group,
      AVG(hypotension_episodes) AS avg_hypotension_episodes,
      AVG(tachycardia_episodes) AS avg_tachycardia_episodes,
      AVG(icu_los) AS avg_icu_los,
      AVG(hospital_expire_flag) AS mortality_rate
    FROM population_metrics
    WHERE
      population_group = 'Top Quartile of Cohort'
    UNION ALL
    SELECT
      'General ICU Population' AS population_group,
      AVG(hypotension_episodes) AS avg_hypotension_episodes,
      AVG(tachycardia_episodes) AS avg_tachycardia_episodes,
      AVG(icu_los) AS avg_icu_los,
      AVG(hospital_expire_flag) AS mortality_rate
    FROM population_metrics
  )

-- Final Step: Combine the 95th percentile report with the comparison table.
SELECT
  f.population_group,
  s.p95_vii_for_cohort,
  f.avg_hypotension_episodes,
  f.avg_tachycardia_episodes,
  f.avg_icu_los,
  f.mortality_rate
FROM final_comparison AS f
CROSS JOIN cohort_vii_stats AS s
ORDER BY
  f.population_group DESC;