WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
ami_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  WHERE 
    (diag.icd_version = 9 AND diag.icd_code LIKE '410%') 
    OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
),
cohort_with_age AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime,
    c.hospital_expire_flag,
    c.anchor_age + (EXTRACT(YEAR FROM c.admittime) - c.anchor_year) AS computed_age
  FROM cohort c
  INNER JOIN ami_admissions a
    ON c.hadm_id = a.hadm_id
  WHERE c.anchor_age + (EXTRACT(YEAR FROM c.admittime) - c.anchor_year) BETWEEN 46 AND 56
),
drg_severity AS (
  SELECT 
    hadm_id, 
    MAX(SAFE_CAST(drg_severity AS INT64)) AS max_drg_severity
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  GROUP BY hadm_id
),
cohort_risk AS (
  SELECT 
    c.*,
    d.max_drg_severity,
    (c.computed_age + d.max_drg_severity) AS risk_score
  FROM cohort_with_age c
  INNER JOIN drg_severity d
    ON c.hadm_id = d.hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM cohort_risk
),
quintile_agg AS (
  SELECT 
    quintile,
    COUNT(*) AS total_patients,
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
    AVG(CASE WHEN max_drg_severity >= 3 THEN 1 ELSE 0 END) * 100 AS major_complication_percent
  FROM quintiles
  GROUP BY quintile
),
survivor_los AS (
  SELECT 
    quintile,
    APPROX_QUANTILES(
      DATETIME_DIFF(dischtime, admittime, SECOND) / 86400.0, 
      100
    )[OFFSET(50)] AS median_survivor_los_days
  FROM quintiles
  WHERE hospital_expire_flag = 0
  GROUP BY quintile
)
SELECT 
  qa.quintile,
  qa.total_patients,
  ROUND(qa.in_hospital_mortality_percent, 2) AS in_hospital_mortality_percent,
  ROUND(qa.major_complication_percent, 2) AS major_complication_percent,
  ROUND(sl.median_survivor_los_days, 2) AS median_survivor_los_days
FROM quintile_agg qa
LEFT JOIN survivor_los sl
  ON qa.quintile = sl.quintile
ORDER BY qa.quintile;