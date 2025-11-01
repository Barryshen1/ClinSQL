WITH patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
),

-- ACS diagnosis using ICD-10 codes
acs_codes AS (
  SELECT 'I21' AS code_prefix, 10 AS version UNION ALL
  SELECT 'I22', 10 UNION ALL
  SELECT 'I20.0', 10
),

acs_patients AS (
  SELECT DISTINCT pa.*
  FROM patients_age pa
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  JOIN acs_codes ac
    ON di.icd_code LIKE CONCAT(ac.code_prefix, '%')
    AND di.icd_version = ac.version
),

non_acs_controls AS (
  SELECT pa.*
  FROM patients_age pa
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    JOIN acs_codes ac
      ON di.icd_code LIKE CONCAT(ac.code_prefix, '%')
      AND di.icd_version = ac.version
    WHERE di.hadm_id = pa.hadm_id
  )
),

-- Lab events in first 72 hours
lab_72h AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.flag,
    di.category
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems di
    ON le.itemid = di.itemid
  WHERE le.charttime IS NOT NULL
    AND le.flag IN ('abnormal', 'high', 'low', 'delta', 'deltaalert')
),

acs_labs AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    COUNT(DISTINCT l.category) AS instability_score
  FROM acs_patients ap
  JOIN lab_72h l
    ON ap.hadm_id = l.hadm_id
    AND l.charttime >= ap.admittime
    AND l.charttime <= DATETIME_ADD(ap.admittime, INTERVAL 72 HOUR)
  GROUP BY ap.subject_id, ap.hadm_id
),

-- Add outcomes to ACS
acs_outcomes AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    COALESCE(al.instability_score, 0) AS instability_score,
    ap.hospital_expire_flag,
    DATETIME_DIFF(ap.dischtime, ap.admittime, SECOND) / (24*3600.0) AS los_days
  FROM acs_patients ap
  LEFT JOIN acs_labs al ON ap.hadm_id = al.hadm_id
),

-- Quartiles for ACS
acs_quartiles AS (
  SELECT
    instability_score,
    hospital_expire_flag,
    los_days,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM acs_outcomes
),

-- Summary by quartile for ACS
quartile_summary AS (
  SELECT
    quartile,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate,
    AVG(los_days) AS avg_los
  FROM acs_quartiles
  GROUP BY quartile
  ORDER BY quartile
),

-- Instability score for controls
control_labs AS (
  SELECT
    nc.subject_id,
    nc.hadm_id,
    COUNT(DISTINCT l.category) AS instability_score
  FROM non_acs_controls nc
  JOIN lab_72h l
    ON nc.hadm_id = l.hadm_id
    AND l.charttime >= nc.admittime
    AND l.charttime <= DATETIME_ADD(nc.admittime, INTERVAL 72 HOUR)
  GROUP BY nc.subject_id, nc.hadm_id
),

control_outcomes AS (
  SELECT
    nc.subject_id,
    nc.hadm_id,
    COALESCE(cl.instability_score, 0) AS instability_score,
    nc.hospital_expire_flag,
    DATETIME_DIFF(nc.dischtime, nc.admittime, SECOND) / (24*3600.0) AS los_days
  FROM non_acs_controls nc
  LEFT JOIN control_labs cl ON nc.hadm_id = cl.hadm_id
),

-- Compare high instability (e.g., score >= 3) between ACS and controls
acs_high_instability AS (
  SELECT COUNT(*) AS count_high, COUNT(*) * 1.0 / (SELECT COUNT(*) FROM acs_outcomes) AS pct_high
  FROM acs_outcomes
  WHERE instability_score >= 3
),
control_high_instability AS (
  SELECT COUNT(*) AS count_high, COUNT(*) * 1.0 / (SELECT COUNT(*) FROM control_outcomes) AS pct_high
  FROM control_outcomes
  WHERE instability_score >= 3
),
comparison AS (
  SELECT
    'ACS' AS group_name,
    pct_high AS pct_high_instability
  FROM acs_high_instability
  UNION ALL
  SELECT
    'Control' AS group_name,
    pct_high AS pct_high_instability
  FROM control_high_instability
)

-- Final output: First part - quartile summary for ACS, second - comparison
SELECT
  CAST(quartile AS STRING) AS group_name,
  ROUND(mortality_rate, 2) AS mortality_pct,
  ROUND(avg_los, 2) AS avg_los_days,
  NULL AS pct_high_instability
FROM quartile_summary
UNION ALL
SELECT
  group_name,
  NULL AS mortality_pct,
  NULL AS avg_los_days,
  ROUND(pct_high_instability * 100, 2) AS pct_high_instability
FROM comparison
ORDER BY group_name;