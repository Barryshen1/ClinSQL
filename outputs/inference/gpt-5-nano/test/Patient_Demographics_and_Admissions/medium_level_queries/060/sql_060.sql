WITH eligible AS (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'Hospice'
      ELSE NULL
    END AS outcome,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (LOWER(a.admission_location) LIKE '%ed%' OR LOWER(a.admission_type) LIKE '%emergency%')
    AND (
      a.hospital_expire_flag = 1
      OR LOWER(a.discharge_location) LIKE '%home%'
      OR LOWER(a.discharge_location) LIKE '%hospice%'
    )
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)

SELECT
  outcome,
  AVG(los_days) AS mean_los_days,
  STDDEV_SAMP(los_days) AS sd_los_days,
  100.0 * SAFE_DIVIDE(SUM(CASE WHEN los_days <= 10.0 THEN 1 ELSE 0 END), COUNT(*)) AS pct_le_10_days
FROM eligible
WHERE outcome IS NOT NULL
GROUP BY outcome
ORDER BY outcome;