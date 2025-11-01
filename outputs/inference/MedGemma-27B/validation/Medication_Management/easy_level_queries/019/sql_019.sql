WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 63 -- Specific patient ID
),
PrescriptionInfo AS (
  SELECT
    p.subject_id,
    p.starttime,
    p.stoptime,
    p.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN
    PatientInfo AS pi ON p.subject_id = pi.subject_id
  WHERE
    p.drug IN ('Heparin', 'Enoxaparin')
    AND p.drug_type = 'Drug'
    AND pi.gender = 'M'
    AND pi.anchor_age BETWEEN 58 AND 68
),
DurationCalculation AS (
  SELECT
    subject_id,
    -- Calculate duration in days, adding 1 to include both start and end day
    (TIMESTAMP_DIFF(stoptime, starttime, DAY) + 1) AS duration_days
  FROM
    PrescriptionInfo
)
SELECT
  PERCENTILE_CONT(duration_days, 0.5) AS median_duration_days
FROM
  DurationCalculation;