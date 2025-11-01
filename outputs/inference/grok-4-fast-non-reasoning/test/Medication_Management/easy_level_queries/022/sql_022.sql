WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_age BETWEEN 59 AND 69
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
),
prescription_durations AS (
  SELECT 
    pr.pharmacy_id,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN 
    eligible_patients ep
  ON 
    pr.subject_id = ep.subject_id
    AND pr.hadm_id = ep.hadm_id
  WHERE 
    (LOWER(pr.drug) LIKE '%amlodipine%'
     OR LOWER(pr.drug) LIKE '%felodipine%'
     OR LOWER(pr.drug) LIKE '%nicardipine%'
     OR LOWER(pr.drug) LIKE '%nifedipine%'
     OR LOWER(pr.drug) LIKE '%nimodipine%'
     OR LOWER(pr.drug) LIKE '%isradipine%')
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
)
SELECT 
  APPROX_QUANTILES(duration_days, 2)[OFFSET(1)] AS median_duration_days
FROM 
  prescription_durations;