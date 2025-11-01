WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.hospital_expire_flag,
    a.discharge_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_type = 'NON-EMERGENCY' -- Filter for non-emergency admissions
),
LOSCalculation AS (
  SELECT
    subject_id,
    -- Calculate Length of Stay (LOS) in days
    -- Use TIMESTAMP_DIFF for accurate day calculation
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM
    PatientInfo
)
SELECT
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, [0.25, 0.5, 0.75, 0.9]) AS quantiles,
  -- Calculate the percentage of patients with LOS <= 14 days
  SUM(CASE WHEN los <= 14 THEN 1 ELSE 0 END) * 100.0 / COUNT(los) AS percent_le_14_days
FROM
  LOSCalculation;