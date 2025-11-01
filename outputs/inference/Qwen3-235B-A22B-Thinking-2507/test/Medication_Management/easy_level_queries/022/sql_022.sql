WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
),
ccb_prescriptions AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.dischtime,
    pr.starttime,
    pr.stoptime,
    COALESCE(LEAST(pr.stoptime, pa.dischtime), pa.dischtime) AS effective_stoptime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pa.subject_id = pr.subject_id AND pa.hadm_id = pr.hadm_id
  WHERE 
    (LOWER(pr.drug) LIKE '%amlodipine%'
     OR LOWER(pr.drug) LIKE '%felodipine%'
     OR LOWER(pr.drug) LIKE '%isradipine%'
     OR LOWER(pr.drug) LIKE '%nicardipine%'
     OR LOWER(pr.drug) LIKE '%nifedipine%'
     OR LOWER(pr.drug) LIKE '%nimodipine%'
     OR LOWER(pr.drug) LIKE '%nisoldipine%')
    AND pr.starttime <= pa.dischtime
),
prescription_durations AS (
  SELECT
    TIMESTAMP_DIFF(effective_stoptime, starttime, HOUR) AS duration_hours
  FROM ccb_prescriptions
  WHERE effective_stoptime >= starttime
)
SELECT
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(50)] AS median_duration_hours
FROM prescription_durations;