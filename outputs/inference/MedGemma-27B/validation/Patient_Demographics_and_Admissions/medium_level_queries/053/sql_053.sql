WITH relevant_admissions AS (
  SELECT
    a.hadm_id,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admittime,
    p.gender,
    p.anchor_age,
    a.discharge_location -- Added discharge_location here
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_type = 'EMERGENCY'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.dischtime IS NOT NULL -- Exclude admissions without discharge time
    AND a.deathtime IS NOT NULL -- Exclude admissions without death time
),
los_calculation AS (
  SELECT
    hadm_id,
    -- Calculate length of stay in days
    -- If patient died in hospital, use deathtime, otherwise use dischtime
    -- Use DATE_DIFF to calculate the difference in days
    DATE_DIFF(
      CASE
        WHEN deathtime IS NOT NULL THEN deathtime
        ELSE dischtime
      END,
      admittime,
      DAY
    ) AS length_of_stay_days
  FROM
    relevant_admissions
)
SELECT
  CASE
    WHEN deathtime IS NOT NULL THEN 'In-hospital death'
    WHEN discharge_location = 'HOME' THEN 'Discharged home'
    WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
    ELSE 'Other' -- Capture other discharge locations if needed
  END AS discharge_category,
  PERCENTILE_CONT(0.5, length_of_stay_days) AS median_los,
  PERCENTILE_CONT(0.25, length_of_stay_days) AS iqr_los_25,
  PERCENTILE_CONT(0.75, length_of_stay_days) AS iqr_los_75
FROM
  los_calculation
LEFT JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON los_calculation.hadm_id = a.hadm_id
GROUP BY
  discharge_category
ORDER BY
  discharge_category;