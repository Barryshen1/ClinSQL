WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_location = 'EMERGENCY'
    AND a.dischtime IS NOT NULL -- Ensure patient was discharged
),
LOSCalculation AS (
  SELECT
    subject_id,
    -- Calculate LOS in days
    (TIMESTAMP_DIFF(dischtime, admittime, DAY) + 1) AS los,
    -- Determine if patient died in hospital
    CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END AS died_in_hospital
  FROM
    PatientInfo
)
SELECT
  died_in_hospital,
  AVG(los) AS mean_los,
  -- Use APPROX_QUANTILES for median calculation
  APPROX_QUANTILES(los, 1)[OFFSET(0.5)] AS median_los,
  COUNT(CASE WHEN los <= 5 THEN 1 ELSE NULL END) * 100.0 / COUNT(los) AS percent_le_5_day_los
FROM
  LOSCalculation
GROUP BY
  died_in_hospital
ORDER BY
  died_in_hospital;