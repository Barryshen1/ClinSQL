WITH first_admissions AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.hospital_expire_flag,
    -- Calculate age at admission using MIMIC-IV standard approach
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
)
SELECT
  PERCENTILE_CONT(age_at_admission, 0.25) OVER () AS p25_age
FROM first_admissions
WHERE rn = 1
  AND age_at_admission BETWEEN 73 AND 83
  AND hospital_expire_flag = 1
LIMIT 1;