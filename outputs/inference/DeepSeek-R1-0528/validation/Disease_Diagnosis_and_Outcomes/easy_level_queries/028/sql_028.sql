WITH cohort AS (
  SELECT 
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admit
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      ON a.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
      ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.services` s 
      ON a.hadm_id = s.hadm_id AND s.transfertime = (
        SELECT MIN(transfertime)
        FROM `physionet-data.mimiciv_3_1_hosp.services` s2
        WHERE s2.hadm_id = a.hadm_id
      )
  WHERE 
    p.gender = 'F'
    AND diag.seq_num = 1
    AND LOWER(d.long_title) LIKE '%pneumonia%'
    AND s.curr_service IN ('EMERGENCY', 'DIRECT EMER')
)
SELECT 
  PERCENTILE_CONT(los_days, 0.25) AS percentile_25
FROM cohort
WHERE age_at_admit BETWEEN 67 AND 77;