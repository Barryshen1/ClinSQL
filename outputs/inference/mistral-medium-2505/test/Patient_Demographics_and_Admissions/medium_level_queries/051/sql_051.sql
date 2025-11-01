WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
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
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
)

SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'Expired'
    ELSE 'Alive'
  END AS discharge_status,
  COUNT(*) AS total_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV(los_days), 2) AS sd_los_days,
  ROUND(100 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_le_7_days
FROM
  filtered_admissions
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;