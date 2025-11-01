WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND a.admission_location = 'EMERGENCY ROOM/ED'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 0
    -- Calculate exact age at admission
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 41 AND 51
)
SELECT
  CASE
    WHEN hospital_expire_flag = 0 THEN 'Alive'
    WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
  END AS discharge_status,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100000)[OFFSET(50000)] AS median_los,
  (SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) * 100.0) / COUNT(*) AS percent_le_5_day_los
FROM
  filtered_admissions
GROUP BY
  discharge_status
ORDER BY
  discharge_status;