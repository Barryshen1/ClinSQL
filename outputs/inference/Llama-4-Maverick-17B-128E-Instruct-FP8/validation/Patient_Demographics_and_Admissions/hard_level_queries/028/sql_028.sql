WITH 
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_num,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND a.insurance = 'Medicare'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id AND d.seq_num = 1 AND dicd.long_title LIKE '%Cellulitis%'
    )
),
index_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_hours
  FROM 
    cohort
  WHERE 
    admission_num = 1
),
readmissions AS (
  SELECT DISTINCT 
    c.subject_id
  FROM 
    cohort c
  INNER JOIN 
    index_admissions ia ON c.subject_id = ia.subject_id
  WHERE 
    c.admission_num > 1
    AND DATETIME_DIFF(c.admittime, ia.dischtime, DAY) BETWEEN 0 AND 30
)
SELECT 
  SAFE_DIVIDE(COUNT(DISTINCT r.subject_id), COUNT(DISTINCT ia.subject_id)) AS readmission_rate,
  APPROX_QUANTILES(CASE WHEN ia.subject_id IN (SELECT subject_id FROM readmissions) THEN ia.los_hours END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN ia.subject_id NOT IN (SELECT subject_id FROM readmissions) THEN ia.los_hours END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  SAFE_DIVIDE(SUM(CASE WHEN ia.los_hours > 7 * 24 THEN 1 ELSE 0 END), COUNT(DISTINCT ia.hadm_id)) AS percent_long_stay
FROM 
  index_admissions ia
  LEFT JOIN readmissions r ON ia.subject_id = r.subject_id;