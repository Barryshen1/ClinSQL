WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    ROUND(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0, 2) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.services` s
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.dischtime IS NOT NULL
    AND s.curr_service LIKE 'MED%'  -- medicine service filter
)
, categorized AS (
  SELECT
    subject_id,
    hadm_id,
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      ELSE 'Other'
    END AS discharge_group
  FROM base
)
SELECT
  discharge_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(APPROX_QUANTILES(los, 2)[OFFSET(1)], 2) AS median_los,
  ROUND(AVG(CASE WHEN los <= 5 THEN 1 ELSE 0 END), 4) AS proportion_los_le_5
FROM categorized
WHERE discharge_group IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY discharge_group
ORDER BY discharge_group;