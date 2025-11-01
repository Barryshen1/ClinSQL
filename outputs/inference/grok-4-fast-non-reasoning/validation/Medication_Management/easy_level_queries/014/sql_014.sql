WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.hospital_expire_flag = 0
    AND a.dischtime > a.admittime
),
prescription_durations AS (
  SELECT 
    pr.subject_id,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) + 1 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN eligible_patients ep
    ON pr.subject_id = ep.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.subject_id = a.subject_id AND pr.hadm_id = a.hadm_id
  WHERE LOWER(pr.drug) LIKE '%atorvastatin%'
    AND pr.dose_val_rx BETWEEN 40 AND 80
    AND pr.dose_unit_rx = 'MG'
    AND pr.stoptime IS NOT NULL
    AND pr.starttime < pr.stoptime  -- Valid duration
    AND pr.starttime >= a.admittime
    AND pr.stoptime <= a.dischtime  -- Within admission
)
SELECT MIN(duration_days) AS min_high_intensity_atorvastatin_days
FROM prescription_durations
WHERE duration_days > 0;