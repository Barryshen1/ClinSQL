WITH
-- Define the cohort: ICU patients aged 43-53 with acute respiratory failure
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.gender,
    p.anchor_age,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    p.anchor_age BETWEEN 43 AND 53
    AND p.gender = 'F'
    AND d.icd_code IN (
      'J9600', 'J9601', 'J9602', 'J9620', 'J9621', 'J9622',  -- Acute respiratory failure codes
      'J9690', 'J9691', 'J9692'
    )
    AND d.icd_version = 10
),

-- Calculate Vital Instability Index (VII) for each patient in first 48 hours
vii_calculation AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.icu_intime,
    c.icu_outtime,
    c.icu_los,
    c.hospital_expire_flag,
    -- Calculate VII components (simplified example - adjust based on clinical definition)
    -- This is a placeholder - actual VII calculation would be more complex
    AVG(CASE WHEN ce.itemid IN (220045, 220050) THEN ce.valuenum ELSE NULL END) AS heart_rate,
    AVG(CASE WHEN ce.itemid IN (220050, 220179) THEN ce.valuenum ELSE NULL END) AS resp_rate,
    AVG(CASE WHEN ce.itemid IN (220179, 220180) THEN ce.valuenum ELSE NULL END) AS spo2,
    -- Calculate VII (example formula - adjust as needed)
    (STDDEV(CASE WHEN ce.itemid IN (220045, 220050) THEN ce.valuenum ELSE NULL END) +
     STDDEV(CASE WHEN ce.itemid IN (220050, 220179) THEN ce.valuenum ELSE NULL END) +
     STDDEV(CASE WHEN ce.itemid IN (220179, 220180) THEN ce.valuenum ELSE NULL END)) AS vii
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (
      220045, 220050, 220179, 220180,  -- Heart rate, respiratory rate, SpO2
      220051, 220052, 220181, 220182    -- Additional vital signs if needed
    )
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, c.icu_intime, c.icu_outtime, c.icu_los, c.hospital_expire_flag
),

-- Get 95th percentile VII for the cohort
vii_stats AS (
  SELECT
    PERCENTILE_CONT(vii, 0.95) OVER() AS vii_95th_percentile
  FROM
    vii_calculation
  LIMIT 1
),

-- Identify top quartile of patients based on VII
top_quartile AS (
  SELECT
    *,
    NTILE(4) OVER(ORDER BY vii DESC) AS quartile
  FROM
    vii_calculation
  WHERE
    vii > (SELECT vii_95th_percentile FROM vii_stats)
),

-- Calculate metrics for top quartile
top_quartile_metrics AS (
  SELECT
    COUNT(DISTINCT tq.subject_id) AS patient_count,
    SUM(CASE WHEN tq.heart_rate > 100 THEN 1 ELSE 0 END) AS tachycardia_episodes,
    SUM(CASE WHEN
          (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
           WHERE ce.stay_id = tq.stay_id AND ce.itemid IN (220050, 220179)
           AND ce.valuenum < 65 AND ce.charttime BETWEEN tq.icu_intime AND tq.icu_outtime) > 0
        THEN 1 ELSE 0 END) AS map_hypotension_episodes,
    AVG(tq.icu_los) AS avg_icu_los,
    SUM(tq.hospital_expire_flag) AS mortality_count
  FROM
    top_quartile tq
),

-- Calculate metrics for general ICU population (same age range)
general_population_metrics AS (
  SELECT
    COUNT(DISTINCT p.subject_id) AS patient_count,
    SUM(CASE WHEN ce.valuenum > 100 AND ce.itemid IN (220045, 220050) THEN 1 ELSE 0 END) AS tachycardia_episodes,
    SUM(CASE WHEN ce.valuenum < 65 AND ce.itemid IN (220050, 220179) THEN 1 ELSE 0 END) AS map_hypotension_episodes,
    AVG(i.los) AS avg_icu_los,
    SUM(a.hospital_expire_flag) AS mortality_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON i.stay_id = ce.stay_id
  WHERE
    p.anchor_age BETWEEN 43 AND 53
    AND p.gender = 'F'
    AND ce.charttime BETWEEN i.intime AND i.outtime
)

-- Final comparison
SELECT
  'Top Quartile (High VII)' AS cohort,
  patient_count,
  tachycardia_episodes,
  map_hypotension_episodes,
  avg_icu_los,
  mortality_count,
  ROUND(mortality_count * 100.0 / patient_count, 2) AS mortality_rate
FROM
  top_quartile_metrics

UNION ALL

SELECT
  'General ICU Population' AS cohort,
  patient_count,
  tachycardia_episodes,
  map_hypotension_episodes,
  avg_icu_los,
  mortality_count,
  ROUND(mortality_count * 100.0 / patient_count, 2) AS mortality_rate
FROM
  general_population_metrics
ORDER BY
  cohort;