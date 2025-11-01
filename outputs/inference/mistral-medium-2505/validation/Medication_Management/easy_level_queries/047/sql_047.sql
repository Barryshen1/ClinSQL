WITH female_patients_60_70 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 60 AND 70
),

admissions_with_prescriptions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    pres.pharmacy_id,
    pres.starttime,
    pres.stoptime,
    pres.drug,
    pres.dose_val_rx,
    TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) AS prescription_duration_days
  FROM
    female_patients_60_70 p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON a.subject_id = pres.subject_id
    AND a.hadm_id = pres.hadm_id
  WHERE
    pres.drug LIKE '%atorvastatin%'
    AND SAFE_CAST(pres.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND pres.stoptime IS NOT NULL
    AND pres.starttime >= a.admittime
    AND pres.stoptime <= a.dischtime
)

SELECT
  APPROX_QUANTILES(prescription_duration_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(prescription_duration_days, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(prescription_duration_days, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(prescription_duration_days, 4)[OFFSET(3)] -
  APPROX_QUANTILES(prescription_duration_days, 4)[OFFSET(1)] AS iqr
FROM
  admissions_with_prescriptions;