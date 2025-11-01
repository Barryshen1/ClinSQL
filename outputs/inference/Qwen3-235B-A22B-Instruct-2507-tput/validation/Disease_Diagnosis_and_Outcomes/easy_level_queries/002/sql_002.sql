WITH aki_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%acute kidney injury%'
     OR LOWER(long_title) LIKE '%acute renal failure%'
),
aki_primary_admissions AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN aki_codes ac
    ON di.icd_code = ac.icd_code AND di.icd_version = ac.icd_version
  WHERE di.seq_num = 1
),
patient_los AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN aki_primary_admissions aki
    ON a.hadm_id = aki.hadm_id
  WHERE p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
)
SELECT
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los_days
FROM patient_los
WHERE age_at_admission >= 52 AND age_at_admission <= 62;