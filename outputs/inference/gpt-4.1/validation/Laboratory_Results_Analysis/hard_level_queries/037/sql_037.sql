WITH
-- 1. Identify hemorrhagic stroke ICD codes
hemorrhagic_stroke_icd AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%'))
    OR
    (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
),

-- 2. Cohort: male, age 70-80, hemorrhagic stroke
cohort_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN hemorrhagic_stroke_icd h ON d.icd_code = h.icd_code AND d.icd_version = h.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 70 AND 80
),

-- 3. General inpatient admissions (for comparison)
general_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

-- 4. Lab instability score for each admission (first 48h)
lab_instability AS (
  SELECT
    l.hadm_id,
    SUM(CAST(is_critical_lab_event AS INT64)) AS critical_lab_events
  FROM (
    SELECT
      l.hadm_id,
      (
        l.flag = 'abnormal'
        OR (
          SAFE_CAST(l.valuenum AS FLOAT64) IS NOT NULL
          AND (
            (l.ref_range_lower IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64))
            OR
            (l.ref_range_upper IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64))
          )
        )
      ) AS is_critical_lab_event
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
    WHERE
      l.charttime >= a.admittime
      AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  ) l
  GROUP BY l.hadm_id
),

-- 5. Merge lab instability with cohort and general admissions
cohort_lab AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    IFNULL(l.critical_lab_events, 0) AS critical_lab_events,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR)/24.0 AS los_days
  FROM cohort_admissions c
  LEFT JOIN lab_instability l ON c.hadm_id = l.hadm_id
),

general_lab AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    g.admittime,
    g.dischtime,
    g.hospital_expire_flag,
    IFNULL(l.critical_lab_events, 0) AS critical_lab_events,
    TIMESTAMP_DIFF(g.dischtime, g.admittime, HOUR)/24.0 AS los_days
  FROM general_admissions g
  LEFT JOIN lab_instability l ON g.hadm_id = l.hadm_id
),

-- 6. Cohort statistics
cohort_stats AS (
  SELECT
    APPROX_QUANTILES(critical_lab_events, 100)[25] AS lab_instability_25th_percentile,
    AVG(critical_lab_events) AS mean_critical_lab_events,
    AVG(los_days) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate,
    COUNT(*) AS n_admissions
  FROM cohort_lab
  WHERE los_days IS NOT NULL
),

-- 7. General inpatient statistics
general_stats AS (
  SELECT
    AVG(critical_lab_events) AS mean_critical_lab_events,
    AVG(los_days) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate,
    COUNT(*) AS n_admissions
  FROM general_lab
  WHERE los_days IS NOT NULL
)

-- 8. Final output
SELECT
  'Cohort: Male, Age 70-80, Hemorrhagic Stroke' AS group,
  lab_instability_25th_percentile,
  mean_critical_lab_events,
  mean_los_days,
  in_hospital_mortality_rate,
  n_admissions
FROM cohort_stats

UNION ALL

SELECT
  'General Inpatient Population' AS group,
  NULL AS lab_instability_25th_percentile,
  mean_critical_lab_events,
  mean_los_days,
  in_hospital_mortality_rate,
  n_admissions
FROM general_stats;