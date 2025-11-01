WITH PatientAge AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 57 AND 67
),
PrescriptionDurations AS (
  SELECT
    pa.subject_id,
    pr.starttime,
    pr.stoptime,
    -- Calculate duration in hours
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pr.hadm_id = a.hadm_id
  JOIN PatientAge AS pa
    ON pr.subject_id = pa.subject_id
  WHERE
    -- Assuming DAPT includes aspirin and clopidogrel
    pr.drug LIKE '%aspirin%' AND pr.drug LIKE '%clopidogrel%'
    AND pr.drug_type = 'medication'
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(duration_hours, 0.25) AS q1,
  PERCENTILE_CONT(duration_hours, 0.75) AS q3
FROM PrescriptionDurations;