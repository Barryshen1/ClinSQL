WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    pat.anchor_age,
    pat.gender,
    -- Calculate LOS in days
    SAFE_CAST(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS FLOAT64) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.anchor_age BETWEEN 88 AND 98
    AND pat.gender = 'M'
    AND adm.admission_type = 'ELECTIVE'
    -- Exclude missing LOS
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
, classified AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%snf%' OR
           LOWER(discharge_location) LIKE '%rehab%' OR
           LOWER(discharge_location) LIKE '%skilled nursing%' OR
           LOWER(discharge_location) LIKE '%ltac%' OR
           LOWER(discharge_location) LIKE '%long term acute care%' OR
           LOWER(discharge_location) LIKE '%extended care%' OR
           LOWER(discharge_location) LIKE '%nursing home%' THEN 'SNF/Rehab/LTACH'
      ELSE 'Other'
    END AS discharge_outcome
  FROM cohort
)
, filtered AS (
  SELECT
    *
  FROM classified
  WHERE discharge_outcome IN ('Home', 'SNF/Rehab/LTACH', 'In-hospital death')
    AND los > 0
)
SELECT
  discharge_outcome,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(50)], 2) AS median_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(75)], 2) AS p75_los,
  ROUND(APPROX_QUANTILES(los, 100)[OFFSET(90)], 2) AS p90_los,
  ROUND(100 * SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_los_le_7
FROM
  filtered
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;