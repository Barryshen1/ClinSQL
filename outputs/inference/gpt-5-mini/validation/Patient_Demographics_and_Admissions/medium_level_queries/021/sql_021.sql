WITH surgical_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 0
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.subject_id = a.subject_id
        AND s.hadm_id = a.hadm_id
        AND LOWER(COALESCE(s.curr_service, '')) LIKE '%surg%'
    )
)

SELECT
  category,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(STDDEV_POP(los_days), 2) AS sd_los_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_le_7
FROM (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%home%' THEN 'Discharged home'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%rehab%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%snf%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%nurs%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%facility%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%long term%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%ltac%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%skilled%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%transfer to%'
        THEN 'Discharged to facility'
      ELSE 'Other'
    END AS category
  FROM surgical_admissions
)
WHERE category IN ('Discharged home', 'Discharged to facility', 'In-hospital mortality')
GROUP BY category
ORDER BY
  CASE category
    WHEN 'Discharged home' THEN 1
    WHEN 'Discharged to facility' THEN 2
    WHEN 'In-hospital mortality' THEN 3
    ELSE 4
  END;