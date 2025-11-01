WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    a.admission_location,
    a.edregtime,
    a.admittime,
    a.dischtime,
    -- LOS in fractional days
    (TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    -- admitted from ED: either edregtime present or admission_location mentions ED/emerg
    AND (a.edregtime IS NOT NULL OR LOWER(a.admission_location) LIKE '%emerg%')
    -- require valid admission and discharge times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- exclude impossible negative LOS
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
)
SELECT
  CASE
    WHEN hospital_expire_flag = 1 THEN 'Died in hospital'
    WHEN hospital_expire_flag = 0 THEN 'Survived to discharge'
    ELSE 'Unknown'
  END AS discharge_status,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los_days), 2) AS sd_los_days,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN los_days <= 7.0 THEN 1 ELSE 0 END), COUNT(*)), 2) AS pct_los_le_7_percent
FROM cohort
GROUP BY hospital_expire_flag
ORDER BY hospital_expire_flag DESC;