WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    svc.curr_service,
    -- Calculate LOS in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.services` svc
    ON adm.hadm_id = svc.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND svc.curr_service = 'MED'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
, discharge_grouped AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE 'Other'
    END AS discharge_group
  FROM cohort
)
, summary AS (
  SELECT
    discharge_group,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) AS n_los_ge_7,
    SUM(CASE WHEN los >= 14 THEN 1 ELSE 0 END) AS n_los_ge_14,
    -- 7-day LOS percentile: percent of admissions with LOS <= 7
    SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*) AS los_le_7_percentile
  FROM discharge_grouped
  WHERE discharge_group IN ('Home', 'Hospice', 'In-hospital death')
  GROUP BY discharge_group
)
SELECT
  discharge_group,
  n_admissions,
  ROUND(n_los_ge_7 / n_admissions, 3) AS prop_los_ge_7,
  ROUND(n_los_ge_14 / n_admissions, 3) AS prop_los_ge_14,
  ROUND(los_le_7_percentile, 3) AS los_le_7_percentile
FROM summary
ORDER BY discharge_group;