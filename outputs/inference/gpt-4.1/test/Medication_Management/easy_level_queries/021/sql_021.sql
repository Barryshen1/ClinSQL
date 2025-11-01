WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 75 AND 85
),
eligible_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients p ON a.subject_id = p.subject_id
),
atorvastatin_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    SAFE_CAST(pr.dose_val_rx AS FLOAT64) AS dose,
    pr.dose_unit_rx,
    pr.drug,
    pr.doses_per_24_hrs
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN eligible_admissions ea ON pr.subject_id = ea.subject_id AND pr.hadm_id = ea.hadm_id
  WHERE
    LOWER(pr.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(pr.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND LOWER(pr.dose_unit_rx) = 'mg'
    AND (pr.doses_per_24_hrs = 1 OR pr.doses_per_24_hrs IS NULL)
    AND NOT (LOWER(pr.drug) LIKE '%ezetimibe%' OR LOWER(pr.drug) LIKE '%combo%' OR LOWER(pr.drug) LIKE '%/%')
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
),
prescription_durations AS (
  SELECT
    subject_id,
    hadm_id,
    drug,
    dose,
    starttime,
    stoptime,
    TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM atorvastatin_prescriptions
  WHERE TIMESTAMP_DIFF(stoptime, starttime, DAY) > 0
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS duration_25th_percentile,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS duration_75th_percentile,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr_days
FROM prescription_durations
;