WITH PatientInfo AS (
  SELECT
    subject_id
  FROM patients
  WHERE
    gender = 'F' AND anchor_age = 48
),
FilteredAdmissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag
  FROM admissions AS a
  JOIN PatientInfo AS pi
    ON a.subject_id = pi.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
    AND a.discharge_location IN ('HOME', 'FACILITY', 'DEAD')
    AND a.admittime BETWEEN TIMESTAMP('2000-01-01') AND TIMESTAMP('2023-12-31') -- Assuming a reasonable date range
),
LOSCalculation AS (
  SELECT
    hadm_id,
    subject_id,
    CASE
      WHEN hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(dischtime, admitime, DAY)
      ELSE TIMESTAMP_DIFF(dischtime, admitime, DAY)
    END AS los
  FROM FilteredAdmissions
)
SELECT
  discharge_location,
  MEDIAN(los) AS median_los,
  PERCENTILE_CONT(0.25, los) AS iqr_25,
  PERCENTILE_CONT(0.75, los) AS iqr_75,
  PERCENTILE_CONT(0.5, los) AS percentile_rank_50 -- Percentile rank of a 14-day stay
FROM LOSCalculation
WHERE
  los = 14
GROUP BY
  discharge_location;