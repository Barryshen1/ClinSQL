WITH index_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
  WHERE 
    diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('43301','43311','43321','43331','43381','43391','43401','43411','43491','436'))
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
    )
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'Medicare'
    AND p.gender = 'M'
    AND adm.hospital_expire_flag = 0
),
index_with_readmission_flag AS (
  SELECT 
    ia.*,
    CASE WHEN n.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmission_flag
  FROM index_admissions ia
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` n 
    ON ia.subject_id = n.subject_id
    AND n.admittime > ia.dischtime 
    AND n.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
  WHERE ia.age_at_admission BETWEEN 76 AND 86
),
stats AS (
  SELECT 
    COUNT(*) AS total_index_admissions,
    SUM(readmission_flag) AS readmission_count,
    SUM(CASE WHEN los_days > 5 THEN 1 ELSE 0 END) AS los_gt_5_count
  FROM index_with_readmission_flag
),
median_group AS (
  SELECT 
    readmission_flag,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
  FROM index_with_readmission_flag
  GROUP BY readmission_flag
)
SELECT 
  ROUND(100.0 * readmission_count / total_index_admissions, 2) AS readmission_rate,
  (SELECT median_los FROM median_group WHERE readmission_flag = 1) AS median_los_readmitted,
  (SELECT median_los FROM median_group WHERE readmission_flag = 0) AS median_los_non_readmitted,
  ROUND(100.0 * los_gt_5_count / total_index_admissions, 2) AS percent_los_gt_5
FROM stats;