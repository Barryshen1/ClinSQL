WITH cohort AS (
  SELECT
    admissions.hadm_id,
    admissions.admittime,
    admissions.dischtime,
    admissions.discharge_location,
    admissions.hospital_expire_flag,
    patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, SECOND) / 86400.0 AS los_days,
    CASE 
      WHEN admissions.discharge_location = 'HOME' THEN 'home'
      WHEN admissions.discharge_location = 'HOSPICE' THEN 'hospice'
      WHEN admissions.hospital_expire_flag = 1 THEN 'in_hospital_death'
    END AS outcome_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` admissions
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON admissions.subject_id = patients.subject_id
  WHERE 
    patients.gender = 'M'
    AND admissions.admission_type = 'ELECTIVE'
    AND admissions.dischtime IS NOT NULL
    AND (admissions.discharge_location IN ('HOME', 'HOSPICE') OR admissions.hospital_expire_flag = 1)
    AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 80 AND 90
)
SELECT
  outcome_group,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS p25,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90,
  SUM(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_los_le_14
FROM cohort
GROUP BY outcome_group
ORDER BY 
  CASE outcome_group
    WHEN 'home' THEN 1
    WHEN 'hospice' THEN 2
    WHEN 'in_hospital_death' THEN 3
  END;