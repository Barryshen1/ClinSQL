WITH med_hadm AS (
  SELECT DISTINCT s.subject_id, s.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.services` AS s
  WHERE LOWER(s.curr_service) LIKE '%medicine%'
),

cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS LOS_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'Hospice'
      ELSE NULL
    END AS discharge_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN med_hadm AS m
    ON m.subject_id = a.subject_id AND m.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  discharge_group,
  COUNT(*) AS total,
  SAFE_DIVIDE(SUM(CASE WHEN LOS_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS prop_ge_7,
  SAFE_DIVIDE(SUM(CASE WHEN LOS_days >= 14 THEN 1 ELSE 0 END), COUNT(*)) AS prop_ge_14,
  APPROX_QUANTILES(LOS_days, 100)[OFFSET(7)] AS p7
FROM cohort
WHERE discharge_group IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY discharge_group
ORDER BY discharge_group;