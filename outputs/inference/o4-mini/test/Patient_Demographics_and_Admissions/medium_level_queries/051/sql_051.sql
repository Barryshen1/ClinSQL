WITH sub AS (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Expired'
      ELSE 'Alive'
    END AS discharge_status,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_location = 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_status,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_POP(los_days), 2) AS sd_los_days,
  ROUND(AVG(IF(los_days <= 7, 1, 0)) * 100, 2) AS pct_los_le_7_days
FROM
  sub
GROUP BY
  discharge_status
ORDER BY
  discharge_status;