WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_location = 'TRANSFER FROM ANOTHER HOSPITAL'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
, discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOME WITH HOME HEALTH', 'HOME WITH HOME CARE') THEN 'Home'
      WHEN discharge_location IN ('HOSPICE-HOME', 'HOSPICE-MEDICAL FACILITY') THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_group
  FROM filtered_admissions
)
, relevant_groups AS (
  SELECT *
  FROM discharge_groups
  WHERE discharge_group IN ('Home', 'Hospice', 'In-hospital death')
)
SELECT
  discharge_group,
  COUNT(*) AS n_total,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS n_LOS_7plus,
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS proportion_LOS_7plus,
  -- Percentile: percent of admissions with LOS <= 7 days
  SAFE_DIVIDE(SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END), COUNT(*)) AS percentile_7day_LOS
FROM
  relevant_groups
GROUP BY
  discharge_group
ORDER BY
  discharge_group;