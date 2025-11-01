WITH
-- Define respiratory failure ICD codes (example codes - adjust as needed)
respiratory_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%respiratory failure%'
),

-- Get male patients aged 40-50 with respiratory failure
eligible_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN respiratory_failure_codes r ON d.icd_code = r.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.hospital_expire_flag IS NOT NULL
),

-- Get MAP and heart rate measurements in first 48 hours
vital_signs AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    e.charttime,
    CASE
      WHEN di.label = 'Mean Blood Pressure' THEN e.valuenum
      ELSE NULL
    END AS map,
    CASE
      WHEN di.label = 'Heart Rate' THEN e.valuenum
      ELSE NULL
    END AS heart_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` e
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON e.itemid = di.itemid
  JOIN eligible_patients ep ON e.subject_id = ep.subject_id AND e.hadm_id = ep.hadm_id AND e.stay_id = ep.stay_id
  WHERE
    (di.label = 'Mean Blood Pressure' OR di.label = 'Heart Rate')
    AND e.charttime BETWEEN ep.icu_intime AND DATETIME_ADD(ep.icu_intime, INTERVAL 48 HOUR)
),

-- Calculate hypotensive and tachycardic burden
burden_metrics AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- Hypotensive burden (percentage of time with MAP < 65)
    SUM(CASE WHEN map < 65 THEN 1 ELSE 0 END) / COUNT(*) AS hypotensive_burden,
    -- Tachycardic burden (percentage of time with HR > 100)
    SUM(CASE WHEN heart_rate > 100 THEN 1 ELSE 0 END) / COUNT(*) AS tachycardic_burden,
    -- Calculate Vital Instability Index (simplified example - adjust formula as needed)
    (SUM(CASE WHEN map < 65 THEN 1 ELSE 0 END) + SUM(CASE WHEN heart_rate > 100 THEN 1 ELSE 0 END)) /
    COUNT(*) AS vii
  FROM vital_signs
  GROUP BY subject_id, hadm_id, stay_id
)

-- Final analysis with statistics
SELECT
  -- Overall statistics
  'Overall' AS group_name,
  COUNT(*) AS patient_count,
  AVG(vii) AS mean_vii,
  STDDEV(vii) AS sd_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(25)] AS percentile_25_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(50)] AS percentile_50_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(75)] AS percentile_75_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(95)] AS percentile_95_vii,
  AVG(hypotensive_burden) AS avg_hypotensive_burden,
  AVG(tachycardic_burden) AS avg_tachycardic_burden,
  AVG(icu_los) AS avg_icu_los,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM burden_metrics b
JOIN eligible_patients e ON b.subject_id = e.subject_id AND b.hadm_id = e.hadm_id AND b.stay_id = e.stay_id

UNION ALL

-- Statistics for hypotensive group
SELECT
  'Hypotensive' AS group_name,
  COUNT(*) AS patient_count,
  AVG(vii) AS mean_vii,
  STDDEV(vii) AS sd_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(25)] AS percentile_25_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(50)] AS percentile_50_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(75)] AS percentile_75_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(95)] AS percentile_95_vii,
  AVG(hypotensive_burden) AS avg_hypotensive_burden,
  AVG(tachycardic_burden) AS avg_tachycardic_burden,
  AVG(icu_los) AS avg_icu_los,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM burden_metrics b
JOIN eligible_patients e ON b.subject_id = e.subject_id AND b.hadm_id = e.hadm_id AND b.stay_id = e.stay_id
WHERE hypotensive_burden > 0.1  -- At least 10% of time with MAP < 65

UNION ALL

-- Statistics for tachycardic group
SELECT
  'Tachycardic' AS group_name,
  COUNT(*) AS patient_count,
  AVG(vii) AS mean_vii,
  STDDEV(vii) AS sd_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(25)] AS percentile_25_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(50)] AS percentile_50_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(75)] AS percentile_75_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(95)] AS percentile_95_vii,
  AVG(hypotensive_burden) AS avg_hypotensive_burden,
  AVG(tachycardic_burden) AS avg_tachycardic_burden,
  AVG(icu_los) AS avg_icu_los,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM burden_metrics b
JOIN eligible_patients e ON b.subject_id = e.subject_id AND b.hadm_id = e.hadm_id AND b.stay_id = e.stay_id
WHERE tachycardic_burden > 0.1  -- At least 10% of time with HR > 100
ORDER BY group_name;