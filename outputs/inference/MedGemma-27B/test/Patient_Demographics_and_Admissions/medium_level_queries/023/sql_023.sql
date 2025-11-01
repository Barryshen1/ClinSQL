WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_type = 'EMERGENCY'
),
LOSCalculation AS (
  SELECT
    subject_id,
    -- Calculate Length of Stay (LOS) in days
    -- Use TIMESTAMP_DIFF to calculate the difference between discharge time and admission time in days
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los,
    -- Calculate 10-day LOS (this is not a standard metric, but interpreting it as LOS if the patient stayed at least 10 days, otherwise 0 or the actual LOS)
    -- Let's calculate the actual LOS for the 10-day percentile rank calculation.
    -- We will calculate the percentile rank based on the actual LOS.
    -- If the question implies a specific calculation for "10-day LOS", clarification is needed. Assuming it means the actual LOS.
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS ten_day_los
  FROM
    PatientCohort
),
LOSPercentile AS (
  SELECT
    subject_id,
    los,
    ten_day_los,
    -- Calculate the percentile rank of the 10-day LOS (actual LOS) among all patients in the cohort
    PERCENTILE_RANK() OVER (ORDER BY ten_day_los) AS los_percentile_rank
  FROM
    LOSCalculation
)
SELECT
  discharge_location,
  COUNT(subject_id) AS total_patients,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) AS patients_los_ge_7,
  -- Calculate the proportion of patients with LOS >= 7 days
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) / COUNT(subject_id) AS proportion_los_ge_7,
  -- Calculate the average percentile rank of 10-day LOS
  AVG(los_percentile_rank) AS avg_los_percentile_rank
FROM
  LOSPercentile
GROUP BY
  discharge_location
ORDER BY
  discharge_location;