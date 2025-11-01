SELECT
  discharge_outcome,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(los_days), 2) AS sd_los_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_leq_10_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(COALESCE(a.discharge_location, '')) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(COALESCE(a.discharge_location, '')) LIKE '%home%' THEN 'home'
      ELSE NULL
    END AS discharge_outcome
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.edregtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
)
WHERE discharge_outcome IS NOT NULL
GROUP BY discharge_outcome
ORDER BY
  CASE discharge_outcome
    WHEN 'home' THEN 1
    WHEN 'hospice' THEN 2
    WHEN 'in-hospital death' THEN 3
    ELSE 4
  END;