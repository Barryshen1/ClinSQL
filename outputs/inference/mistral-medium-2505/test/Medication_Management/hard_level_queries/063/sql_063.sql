WITH
-- Define age range and gender filter
male_patients_48_58 AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 48 AND 58
),

-- Get pneumonia admissions
pneumonia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM male_patients_48_58)
    AND (di.icd_code LIKE 'J12%' OR di.icd_code LIKE 'J13%' OR di.icd_code LIKE 'J14%'
         OR di.icd_code LIKE 'J15%' OR di.icd_code LIKE 'J16%' OR di.icd_code LIKE 'J17%'
         OR di.icd_code LIKE 'J18%')
),

-- Get first 24-hour medications
first_24h_meds AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.route
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    pneumonia_admissions pa
  ON
    p.hadm_id = pa.hadm_id
  WHERE
    TIMESTAMP_DIFF(p.starttime, pa.admittime, HOUR) <= 24
),

-- Calculate medication complexity (count of distinct meds)
med_complexity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS med_count,
    COUNT(DISTINCT CASE WHEN route IN ('IV', 'IVPB', 'IVPUSH') THEN drug END) AS iv_med_count,
    COUNT(DISTINCT CASE WHEN route NOT IN ('IV', 'IVPB', 'IVPUSH') THEN drug END) AS non_iv_med_count
  FROM
    first_24h_meds
  GROUP BY
    subject_id, hadm_id
),

-- Identify serotonergic medications (example list - adjust as needed)
serotonergic_meds AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT CASE WHEN LOWER(drug) IN (
      'fluoxetine', 'sertraline', 'paroxetine', 'citalopram', 'escitalopram',
      'venlafaxine', 'duloxetine', 'tramadol', 'trazodone', 'mirtazapine'
    ) THEN drug END) AS serotonergic_count
  FROM
    first_24h_meds
  GROUP BY
    subject_id, hadm_id
),

-- Combine all data
patient_data AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.los_hours,
    pa.hospital_expire_flag,
    mc.med_count,
    mc.iv_med_count,
    mc.non_iv_med_count,
    sm.serotonergic_count,
    CASE WHEN sm.serotonergic_count >= 2 THEN 1 ELSE 0 END AS high_serotonergic_risk,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = pa.hadm_id
    ) THEN 1 ELSE 0 END AS icu_patient
  FROM
    pneumonia_admissions pa
  LEFT JOIN
    med_complexity mc
  ON
    pa.subject_id = mc.subject_id AND pa.hadm_id = mc.hadm_id
  LEFT JOIN
    serotonergic_meds sm
  ON
    pa.subject_id = sm.subject_id AND pa.hadm_id = sm.hadm_id
),

-- Calculate quartiles for LOS and mortality
quartiles AS (
  SELECT
    PERCENTILE_CONT(los_hours, 0.25) OVER() AS los_p25,
    PERCENTILE_CONT(los_hours, 0.5) OVER() AS los_p50,
    PERCENTILE_CONT(los_hours, 0.75) OVER() AS los_p75,
    PERCENTILE_CONT(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END, 0.25) OVER() AS mort_p25,
    PERCENTILE_CONT(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END, 0.5) OVER() AS mort_p50,
    PERCENTILE_CONT(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END, 0.75) OVER() AS mort_p75
  FROM
    patient_data
  LIMIT 1
),

-- Pre-calculate medication complexity percentiles
med_complexity_stats AS (
  SELECT
    AVG(med_count) AS mean_med_count,
    PERCENTILE_CONT(med_count, 0.25) OVER() AS p25_med_count,
    PERCENTILE_CONT(med_count, 0.5) OVER() AS p50_med_count,
    PERCENTILE_CONT(med_count, 0.75) OVER() AS p75_med_count
  FROM
    patient_data
  LIMIT 1
)

-- Final results
SELECT
  'Medication Complexity' AS metric,
  mean_med_count AS mean,
  p25_med_count AS p25,
  p50_med_count AS p50,
  p75_med_count AS p75
FROM
  med_complexity_stats
UNION ALL
SELECT
  'LOS Comparison' AS metric,
  AVG(CASE WHEN high_serotonergic_risk = 1 THEN los_hours ELSE NULL END) AS serotonergic_los,
  AVG(CASE WHEN icu_patient = 1 THEN los_hours ELSE NULL END) AS icu_los,
  NULL AS p25,
  NULL AS p50,
  NULL AS p75
FROM
  patient_data
UNION ALL
SELECT
  'Mortality Comparison' AS metric,
  AVG(CASE WHEN high_serotonergic_risk = 1 THEN hospital_expire_flag ELSE NULL END) AS serotonergic_mort,
  AVG(CASE WHEN icu_patient = 1 THEN hospital_expire_flag ELSE NULL END) AS icu_mort,
  NULL AS p25,
  NULL AS p50,
  NULL AS p75
FROM
  patient_data
UNION ALL
SELECT
  'Top Quartile LOS' AS metric,
  AVG(CASE WHEN los_hours > (SELECT los_p75 FROM quartiles) THEN los_hours ELSE NULL END) AS top_quartile_los,
  NULL AS p25,
  NULL AS p50,
  NULL AS p75
FROM
  patient_data
UNION ALL
SELECT
  'Top Quartile Mortality' AS metric,
  AVG(CASE WHEN hospital_expire_flag = 1 AND los_hours > (SELECT los_p75 FROM quartiles) THEN 1 ELSE NULL END) AS top_quartile_mort,
  NULL AS p25,
  NULL AS p50,
  NULL AS p75
FROM
  patient_data;