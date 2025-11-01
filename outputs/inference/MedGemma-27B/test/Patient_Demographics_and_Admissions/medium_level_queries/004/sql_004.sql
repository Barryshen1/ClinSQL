WITH PatientCohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    a.admission_type,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type = 'ELECTIVE'
),
LOSCalculation AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.dischtime,
    pc.discharge_location,
    pc.hospital_expire_flag,
    pc.admittime,
    -- Calculate LOS in days
    -- Use TIMESTAMP_DIFF to calculate the difference between discharge time and admission time in days
    -- Add 1 to include the day of admission
    (TIMESTAMP_DIFF(pc.dischtime, pc.admittime, DAY) + 1) AS los
  FROM
    PatientCohort AS pc
)
SELECT
  discharge_location,
  hospital_expire_flag,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(los, 0.5) AS median_los, -- Replaced MEDIAN with PERCENTILE_CONT(los, 0.5)
  PERCENTILE_CONT(los, 0.75) AS p75_los,
  PERCENTILE_CONT(los, 0.90) AS p90_los,
  -- Calculate the percentage of patients with LOS < 5 days
  SUM(CASE WHEN los < 5 THEN 1 ELSE 0 END) * 100.0 / COUNT(los) AS percent_los_lt_5_days
FROM
  LOSCalculation
GROUP BY
  discharge_location,
  hospital_expire_flag
ORDER BY
  discharge_location,
  hospital_expire_flag;