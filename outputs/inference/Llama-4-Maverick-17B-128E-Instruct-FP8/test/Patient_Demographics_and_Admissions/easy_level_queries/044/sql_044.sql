WITH first_admissions AS (
  SELECT p.subject_id, 
         a.hadm_id, 
         a.hospital_expire_flag,
         (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN (
    SELECT subject_id, 
           hadm_id, 
           admittime, 
           hospital_expire_flag,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ) a
  ON p.subject_id = a.subject_id
  WHERE a.rn = 1 AND p.gender = 'M'
)
SELECT APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(25)] AS quantile_25th
FROM first_admissions
WHERE age_at_admission BETWEEN 73 AND 83;