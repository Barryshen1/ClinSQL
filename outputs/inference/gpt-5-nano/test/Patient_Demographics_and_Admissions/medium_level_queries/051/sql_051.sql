WITH coh AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE UPPER(a.admission_type) = 'EMERGENCY'
    AND p.gender = 'Male'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.dischtime IS NOT NULL
    AND a.discharge_location IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
)
SELECT
  discharge_location AS discharge_status,
  AVG(los_days) AS mean_los_days,
  STDDEV_POP(los_days) AS sd_los_days,
  100.0 * SUM(CASE WHEN los_days <= 7.0 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_le7
FROM coh
GROUP BY discharge_status
ORDER BY discharge_status;