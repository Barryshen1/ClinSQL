WITH relevant_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime, -- Corrected column name
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.admission_type = 'EMERGENCY' -- Assuming 'medicine' inpatients are typically admitted via emergency
    AND a.dischtime IS NOT NULL -- Exclude patients who are still admitted
),
los_calculation AS (
  SELECT
    hadm_id,
    subject_id,
    discharge_location,
    -- Calculate LOS in days
    -- Use TIMESTAMP_DIFF for accurate day calculation
    TIMESTAMP_DIFF(dischtime, admitime, DAY) AS los_days -- Corrected column name
  FROM
    relevant_admissions
),
discharge_status AS (
  SELECT
    hadm_id,
    subject_id,
    discharge_location,
    los_days,
    CASE
      WHEN deathtime IS NOT NULL THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Discharge home'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      ELSE 'Other' -- Capture other discharge locations if needed
    END AS discharge_status
  FROM
    los_calculation
)
SELECT
  discharge_status,
  AVG(los_days) AS mean_los,
  MEDIAN(los_days) AS median_los,
  COUNT(CASE WHEN los_days <= 5 THEN 1 END) * 1.0 / COUNT(hadm_id) AS proportion_los_le_5_days
FROM
  discharge_status
GROUP BY
  discharge_status
ORDER BY
  discharge_status;