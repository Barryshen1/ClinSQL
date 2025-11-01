WITH first_admission AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age
  FROM first_admission fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fa.subject_id = p.subject_id
  WHERE 
    fa.admission_rank = 1  -- First admission only
    AND p.gender = 'M'     -- Male
    AND p.anchor_age BETWEEN 73 AND 83  -- Age filter
    AND fa.hospital_expire_flag = 1     -- Died in-hospital
)
SELECT 
  APPROX_QUANTILES(anchor_age, 100)[OFFSET(25)] AS percentile_25th_age
FROM cohort;