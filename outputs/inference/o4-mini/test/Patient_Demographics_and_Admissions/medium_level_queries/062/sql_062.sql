WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.discharge_location,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.dischtime IS NOT NULL
),
with_groups AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN UPPER(discharge_location) LIKE '%SNF%' 
        OR UPPER(discharge_location) LIKE '%REHAB%' 
        OR UPPER(discharge_location) LIKE '%LTACH%' 
        THEN 'SNF/rehab/LTACH'
      WHEN UPPER(discharge_location) = 'HOME' THEN 'home'
      ELSE NULL
    END AS discharge_group
  FROM cohort
)
SELECT
  discharge_group,
  COUNT(*) AS total_n,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS n_los_ge7,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)), 3) AS prop_los_ge7,
  SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS n_los_ge14,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END), COUNT(*)), 3) AS prop_los_ge14
FROM
  with_groups
WHERE
  discharge_group IS NOT NULL
GROUP BY
  discharge_group
ORDER BY
  discharge_group;