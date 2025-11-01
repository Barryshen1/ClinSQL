WITH cohort AS (
  SELECT
    patients.subject_id,
    admissions.hadm_id,
    patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
    ON patients.subject_id = admissions.subject_id
  WHERE
    patients.gender = 'F'
    AND admissions.hospital_expire_flag = 1  -- Died in-hospital
    AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 51 AND 61
)

SELECT
  quartiles[OFFSET(1)] AS q1_age,
  quartiles[OFFSET(3)] AS q3_age,
  quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS iqr_age
FROM (
  SELECT APPROX_QUANTILES(age_at_admission, 4) AS quartiles
  FROM cohort
);