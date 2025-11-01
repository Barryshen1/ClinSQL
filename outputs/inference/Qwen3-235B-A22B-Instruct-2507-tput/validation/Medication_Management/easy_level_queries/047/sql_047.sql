WITH patient_prescriptions AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.drug,
    pr.dose_val_rx,
    pr.dose_unit_rx,
    pr.starttime,
    pr.stoptime,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON a.hadm_id = pr.hadm_id
  WHERE p.gender = 'F'
    AND LOWER(pr.drug) LIKE '%atorvastatin%'
    AND UPPER(pr.dose_unit_rx) = 'MG'
    AND pr.dose_val_rx IS NOT NULL
    AND pr.dose_val_rx >= 40
    AND pr.dose_val_rx <= 80
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
),
prescription_durations AS (
  SELECT
    subject_id,
    hadm_id,
    dose_val_rx,
    DATETIME_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM patient_prescriptions
  WHERE age_at_admit >= 60 AND age_at_admit <= 70
)
SELECT
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(750)] -
  APPROX_QUANTILES(duration_days, 1000)[OFFSET(250)] AS iqr_days
FROM prescription_durations;