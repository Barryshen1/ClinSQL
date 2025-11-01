WITH durations AS (
  SELECT
    DATE_DIFF(prescriptions.stoptime, prescriptions.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS prescriptions
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
    ON prescriptions.subject_id = admissions.subject_id
    AND prescriptions.hadm_id = admissions.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
    ON prescriptions.subject_id = patients.subject_id
  WHERE
    patients.gender = 'F'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 75 AND 85
    AND LOWER(prescriptions.drug) LIKE '%atorvastatin%'
    AND CAST(prescriptions.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND prescriptions.dose_unit_rx = 'mg'
    AND prescriptions.stoptime IS NOT NULL
    AND prescriptions.starttime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(duration_days, 0.75) OVER () - PERCENTILE_CONT(duration_days, 0.25) OVER () AS iqr
FROM durations
LIMIT 1;