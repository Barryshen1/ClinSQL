WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),
t2dm_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'type\s*2|type\s*ii') 
    AND REGEXP_CONTAINS(LOWER(long_title), r'diabetes')
),
hf_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'heart failure')
),
cohort_dx AS (
  SELECT c.*
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN t2dm_codes t2
      ON di.icd_code = t2.icd_code 
      AND di.icd_version = t2.icd_version
    WHERE di.hadm_id = c.hadm_id
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN hf_codes hf
      ON di.icd_code = hf.icd_code 
      AND di.icd_version = hf.icd_version
    WHERE di.hadm_id = c.hadm_id
  )
),
glp1_flags AS (
  SELECT 
    cd.hadm_id,
    MAX(CASE 
          WHEN rx.starttime BETWEEN cd.admittime AND DATETIME_ADD(cd.admittime, INTERVAL 72 HOUR) 
          THEN 1 ELSE 0 
        END) AS in_first_72h,
    MAX(CASE 
          WHEN rx.starttime BETWEEN DATETIME_SUB(cd.dischtime, INTERVAL 12 HOUR) AND cd.dischtime 
          THEN 1 ELSE 0 
        END) AS in_final_12h
  FROM cohort_dx cd
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON cd.hadm_id = rx.hadm_id
    AND LOWER(rx.drug) IN (
          'exenatide', 'liraglutide', 'dulaglutide', 
          'semaglutide', 'lixisenatide', 'albiglutide'
        )
  GROUP BY cd.hadm_id
)
SELECT 
  COUNT(*) AS total_patients,
  SUM(in_first_72h) AS count_first_72h,
  SUM(in_final_12h) AS count_final_12h,
  ROUND(100.0 * SUM(in_first_72h) / COUNT(*), 2) AS pct_first_72h,
  ROUND(100.0 * SUM(in_final_12h) / COUNT(*), 2) AS pct_final_12h,
  ROUND(ABS(
    100.0 * SUM(in_first_72h) / COUNT(*) - 
    100.0 * SUM(in_final_12h) / COUNT(*)
  ), 2) AS abs_diff_pp
FROM glp1_flags;