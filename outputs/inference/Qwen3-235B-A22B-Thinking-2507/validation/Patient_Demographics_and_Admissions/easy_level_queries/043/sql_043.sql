WITH base AS (
  SELECT
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND a.hospital_expire_flag = 1
),
filtered AS (
  SELECT age_at_admission
  FROM base
  WHERE age_at_admission BETWEEN 51 AND 61
)
SELECT
  APPROX_QUANTILES(age_at_admission, 1000)[OFFSET(750)] 
  - APPROX_QUANTILES(age_at_admission, 1000)[OFFSET(250)] AS iqr_age
FROM filtered;