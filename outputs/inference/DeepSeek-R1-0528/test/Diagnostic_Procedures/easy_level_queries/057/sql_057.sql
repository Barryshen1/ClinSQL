WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 64 AND 74
),
proc_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    (icd_version = 9 AND icd_code IN ('3721', '3722', '3723'))
    OR
    (icd_version = 10 AND 
      REGEXP_CONTAINS(LOWER(long_title), r'cardiac catheterization') AND 
      (REGEXP_CONTAINS(LOWER(long_title), r'diagnostic') OR 
       REGEXP_CONTAINS(LOWER(long_title), r'measurement'))
    )
),
patient_procedures AS (
  SELECT 
    c.subject_id,
    COUNT(proc.icd_code) AS num_procedures
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON c.subject_id = proc.subject_id
  LEFT JOIN proc_codes pc
    ON proc.icd_code = pc.icd_code
    AND proc.icd_version = pc.icd_version
  GROUP BY c.subject_id
)
SELECT 
  MIN(num_procedures) AS min_procedures_per_patient
FROM patient_procedures;