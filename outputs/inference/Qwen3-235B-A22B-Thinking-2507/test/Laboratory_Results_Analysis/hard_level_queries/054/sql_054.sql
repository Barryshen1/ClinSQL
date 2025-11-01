WITH ami_admissions AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND d.icd_version = 10
    AND d.icd_code IN (
      'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',
      'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9'
    )
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 38 AND 48
),
ami_admissions_dedup AS (
  SELECT DISTINCT 
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM ami_admissions
  WHERE dischtime IS NOT NULL  -- Ensure valid inpatient stays
),
lab_counts AS (
  SELECT 
    a.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM ami_admissions_dedup a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l
    ON a.hadm_id = l.hadm_id
    AND l.charttime >= a.admittime
    AND l.charttime < a.admittime + INTERVAL '72' HOUR
    AND l.flag = 'critical'
  GROUP BY a.hadm_id
),
with_quartile AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    l.critical_lab_count,
    NTILE(4) OVER (ORDER BY l.critical_lab_count ASC) AS quartile
  FROM ami_admissions_dedup a
  LEFT JOIN lab_counts l
    ON a.hadm_id = l.hadm_id
)
SELECT 
  quartile,
  COUNT(*) AS patient_count,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM with_quartile
GROUP BY quartile
ORDER BY quartile;