WITH PatientAge AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    discharge_location,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    anchor_age BETWEEN 88 AND 98
    AND admission_type = 'ELECTIVE'
),
DischargeOutcome AS (
  SELECT
    hadm_id,
    CASE
      WHEN discharge_location = 'HOME' THEN 'HOME'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'SNF/REHAB/LTACH'
      WHEN hospital_expire_flag = 1 THEN 'IN-HOSPITAL DEATH'
      ELSE 'OTHER'
    END AS discharge_outcome
  FROM
    PatientAge
),
LOSCalculation AS (
  SELECT
    hadm_id,
    discharge_outcome,
    CASE
      WHEN deathtime IS NOT NULL THEN TIMESTAMP_DIFF(deathtime, admit_time, DAY)
      ELSE TIMESTAMP_DIFF(dischtime, admit_time, DAY)
    END AS los
  FROM
    PatientAge
  LEFT JOIN
    DischargeOutcome ON PatientAge.hadm_id = DischargeOutcome.hadm_id
)
SELECT
  discharge_outcome,
  AVG(los) AS mean_los,
  MEDIAN(los) AS median_los,
  PERCENTILE_CONT(los, 0.75) AS p75_los,
  PERCENTILE_CONT(los, 0.90) AS p90_los,
  SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(hadm_id) * 100 AS percent_los_le_7_days
FROM
  LOSCalculation
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;