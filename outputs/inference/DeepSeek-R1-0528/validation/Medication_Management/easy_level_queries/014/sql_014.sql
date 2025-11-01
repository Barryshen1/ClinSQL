WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 86 AND 96
),
atorvastatin_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    SAFE_CAST(pr.dose_val_rx AS FLOAT64) AS dose_val,
    pr.doses_per_24_hrs,
    pr.dose_unit_rx,
    pr.starttime,
    pr.stoptime,
    (SAFE_CAST(pr.dose_val_rx AS FLOAT64) * pr.doses_per_24_hrs) AS daily_dose
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
    AND c.hadm_id = pr.hadm_id
  WHERE
    LOWER(pr.drug) LIKE '%atorvastatin%'
    AND LOWER(pr.dose_unit_rx) = 'mg'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND SAFE_CAST(pr.dose_val_rx AS FLOAT64) IS NOT NULL
    AND pr.doses_per_24_hrs IS NOT NULL
)
SELECT
  MIN(DATE_DIFF(DATE(stoptime), DATE(starttime), DAY)) AS min_duration_days
FROM atorvastatin_prescriptions
WHERE daily_dose BETWEEN 40 AND 80;