WITH surgical_males_67_77 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admission_type LIKE '%SURGICAL%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

discharge_groups AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
      WHEN LOWER(discharge_location) = 'home' THEN 'Discharged home'
      WHEN LOWER(discharge_location) LIKE '%facility%' THEN 'Discharged to facility'
      ELSE 'Other/Unknown'
    END AS discharge_group
  FROM
    surgical_males_67_77
)

SELECT
  discharge_group,
  COUNT(*) AS patient_count,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(STDDEV(los_days), 2) AS sd_los,
  ROUND(100 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_los_le_7_days
FROM
  discharge_groups
WHERE
  discharge_group IN ('Discharged home', 'Discharged to facility', 'In-hospital mortality')
GROUP BY
  discharge_group
ORDER BY
  discharge_group;