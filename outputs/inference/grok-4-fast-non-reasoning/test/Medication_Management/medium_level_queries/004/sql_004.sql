WITH cohort AS (
  -- Base cohort: males 45-55 with T2DM and heart failure
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON CAST(a.hadm_id AS STRING) = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND a.dischtime IS NOT NULL
    AND (
      -- T2DM: ICD-10 E11.*, ICD-9 250.4*
      (d.icd_version = '10' AND d.icd_code LIKE 'E11.%') OR
      (d.icd_version = '9' AND d.icd_code LIKE '250.4%')
    )
    AND (
      -- Heart failure: ICD-10 I50.*, ICD-9 428.*
      (d.icd_version = '10' AND d.icd_code LIKE 'I50.%') OR
      (d.icd_version = '9' AND d.icd_code LIKE '428.%')
    )
    AND d.seq_num <= 10  -- Principal/secondary diagnoses
),

glp1_starts_72h AS (
  -- GLP-1 starts within 72h of admission (using prescriptions for hospital orders)
  SELECT DISTINCT 
    c.subject_id,
    c.hadm_id,
    MIN(pr.starttime) AS first_glp1_time
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON CAST(c.hadm_id AS STRING) = pr.hadm_id
  WHERE REGEXP_CONTAINS(LOWER(pr.drug), r'(semaglutide|liraglutide|dulaglutide|exenatide|albiglutide|lixisenatide)')
    AND pr.starttime >= c.admittime
    AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),

glp1_last48h AS (
  -- GLP-1 administration in last 48h of admission
  SELECT DISTINCT 
    c.subject_id,
    c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON CAST(c.hadm_id AS STRING) = pr.hadm_id
  WHERE REGEXP_CONTAINS(LOWER(pr.drug), r'(semaglutide|liraglutide|dulaglutide|exenatide|albiglutide|lixisenatide)')
    AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
    AND pr.starttime <= c.dischtime
)

-- Final aggregation at patient level
SELECT 
  COUNT(DISTINCT c.subject_id) AS total_patients,
  COUNT(DISTINCT gs.subject_id) AS num_started_72h,
  ROUND((COUNT(DISTINCT gs.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id)), 2) AS pct_started_72h,
  COUNT(DISTINCT gl.subject_id) AS num_last48h,
  ROUND((COUNT(DISTINCT gl.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id)), 2) AS pct_last48h,
  ROUND(
    ((COUNT(DISTINCT gl.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id)) - 
     (COUNT(DISTINCT gs.subject_id) * 100.0 / COUNT(DISTINCT c.subject_id))), 
    2
  ) AS net_change_pct
FROM cohort c
LEFT JOIN glp1_starts_72h gs 
  ON c.subject_id = gs.subject_id
LEFT JOIN glp1_last48h gl 
  ON c.subject_id = gl.subject_id;