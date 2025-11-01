WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admittime_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
age_at_admission AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    anchor_age + (admittime_year - anchor_year) AS age
  FROM patient_admissions
),
filtered_admissions AS (
  SELECT
    hospital_expire_flag
  FROM age_at_admission
  WHERE age >= 51 AND age <= 61
)
SELECT
  PERCENTILE_CONT(hospital_expire_flag, 0.75) OVER () -
  PERCENTILE_CONT(hospital_expire_flag, 0.25) OVER () AS iqr_mortality
FROM filtered_admissions
LIMIT 1;