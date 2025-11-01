WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 56 AND 66
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),
diagnoses AS (
  SELECT 
    d.hadm_id,
    MAX(CASE WHEN d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_heart_failure
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN eligible_admissions e ON d.hadm_id = e.hadm_id
  GROUP BY d.hadm_id
  HAVING has_diabetes = 1 AND has_heart_failure = 1
),
glp1_prescriptions AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%liraglutide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%semaglutide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%exenatide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%dulaglutide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%tirzepatide%' THEN 1
      ELSE 0 
    END AS is_glp1
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN eligible_admissions e ON p.hadm_id = e.hadm_id
),
first48_flags AS (
  SELECT 
    e.hadm_id,
    COALESCE(MAX(CASE WHEN gp.is_glp1 = 1 THEN 1 ELSE 0 END), 0) AS first48_flag
  FROM eligible_admissions e
  LEFT JOIN glp1_prescriptions gp 
    ON e.hadm_id = gp.hadm_id
    AND gp.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 48 HOUR)
  GROUP BY e.hadm_id
),
final24_flags AS (
  SELECT 
    e.hadm_id,
    COALESCE(MAX(CASE WHEN gp.is_glp1 = 1 THEN 1 ELSE 0 END), 0) AS final24_flag
  FROM eligible_admissions e
  LEFT JOIN glp1_prescriptions gp 
    ON e.hadm_id = gp.hadm_id
    AND gp.starttime BETWEEN TIMESTAMP_SUB(e.dischtime, INTERVAL 24 HOUR) AND e.dischtime
  GROUP BY e.hadm_id
)
SELECT 
  COUNT(*) AS total_admissions,
  SUM(first48_flag) AS count_first48,
  SUM(final24_flag) AS count_final24,
  (SUM(first48_flag) * 100.0 / COUNT(*)) AS prevalence_first48_percent,
  (SUM(final24_flag) * 100.0 / COUNT(*)) AS prevalence_final24_percent,
  (SUM(final24_flag) - SUM(first48_flag)) * 100.0 / COUNT(*) AS net_change_percent
FROM diagnoses d
INNER JOIN first48_flags f48 ON d.hadm_id = f48.hadm_id
INNER JOIN final24_flags f24 ON d.hadm_id = f24.hadm_id;