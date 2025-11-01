WITH sepsis_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND (
      d.icd_code LIKE 'A41%' 
      OR d.icd_code = 'R65.2'
    )
    AND a.deathtime IS NULL
    AND a.dischtime > a.admittime  -- Valid LOS
)

SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los_days) OVER() AS los_q1,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) OVER() AS los_q3,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY los_days) OVER() AS los_median,
  COUNT(*) AS cohort_size,
  AVG(los_days) AS los_mean
FROM 
  sepsis_cohort
WHERE 
  los_days > 0;