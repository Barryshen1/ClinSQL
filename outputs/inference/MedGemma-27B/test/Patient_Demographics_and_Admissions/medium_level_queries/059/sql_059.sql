WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admission_location,
    a.discharge_location,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admittime -- Added admittime here
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_location = 'TRANSFER FROM OTHER HOSPITAL'
),
LOSCalculation AS (
  SELECT
    pi.subject_id,
    pi.discharge_location,
    pi.dischtime,
    pi.deathtime,
    pi.hospital_expire_flag,
    -- Calculate length of stay (LOS) in days
    -- Use TIMESTAMP_DIFF for accurate day calculation
    TIMESTAMP_DIFF(
      COALESCE(pi.dischtime, pi.deathtime),
      pi.admittime, -- Use admittime from PatientInfo CTE
      DAY
    ) AS los_days
  FROM
    PatientInfo AS pi
    -- No need to join admissions again, admittime is already in PatientInfo
),
LOSGroup AS (
  SELECT
    discharge_location,
    los_days
  FROM
    LOSCalculation
  WHERE
    los_days >= 7
)
SELECT
  discharge_location,
  COUNT(los_days) AS count_los_ge_7,
  SUM(los_days) AS total_los_ge_7,
  AVG(los_days) AS avg_los_ge_7,
  APPROX_QUANTILES(los_days, 100)[OFFSET(70)] AS percentile_70 -- 70th percentile for 7-day percentile
FROM
  LOSGroup
GROUP BY
  discharge_location;