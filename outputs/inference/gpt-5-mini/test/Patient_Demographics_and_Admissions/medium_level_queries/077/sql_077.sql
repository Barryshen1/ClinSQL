WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag,
    -- LOS in days as fractional days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    -- admitted from the ED (has ED registration time)
    AND a.edregtime IS NOT NULL
    -- ensure valid admission/discharge times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
)

SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
    ELSE 'Discharged alive'
  END AS outcome,
  COUNT(*) AS admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- approximate median
  ROUND(APPROX_QUANTILES(los_days, 2)[OFFSET(1)], 2) AS median_los_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_le_5_days
FROM cohort
GROUP BY hospital_expire_flag
ORDER BY hospital_expire_flag DESC;