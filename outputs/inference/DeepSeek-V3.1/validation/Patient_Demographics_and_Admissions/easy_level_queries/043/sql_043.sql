WITH admission_ages AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
)
SELECT 
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(25)] AS q25_mortality,
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(75)] AS q75_mortality,
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(75)] - APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(25)] AS iqr_mortality
FROM admission_ages
WHERE age_at_admission BETWEEN 51 AND 61;