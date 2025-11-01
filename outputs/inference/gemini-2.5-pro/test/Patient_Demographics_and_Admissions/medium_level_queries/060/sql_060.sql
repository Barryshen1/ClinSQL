WITH cohort AS (
  SELECT
    a.hadm_id,
    -- Calculate LOS in fractional days for more precise statistics
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    -- Categorize discharge outcome, prioritizing the death flag
    CASE
      WHEN a.hospital_expire_flag = 1
        THEN 'In-hospital Death'
      WHEN a.discharge_location = 'HOSPICE'
        THEN 'Hospice'
      WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE')
        THEN 'Home'
      ELSE NULL
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    -- Filter for female patients
    p.gender = 'F'
    -- Filter for admissions from the Emergency Department
    AND a.admission_location = 'EMERGENCY DEPARTMENT'
    -- Calculate age at admission and filter for the 50-60 age group
    AND ((EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age) BETWEEN 50 AND 60
)
-- Final aggregation to calculate the required statistics for each outcome
SELECT
  discharge_outcome,
  COUNT(hadm_id) AS number_of_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS stddev_los_days,
  ROUND(COUNTIF(los_days <= 10) * 100.0 / COUNT(hadm_id), 1) AS percent_los_le_10_days
FROM
  cohort
-- Exclude admissions that do not match the desired outcomes
WHERE
  discharge_outcome IS NOT NULL
GROUP BY
  discharge_outcome
ORDER BY
  -- Order for consistent output
  discharge_outcome;