WITH filtered AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital mortality'
      ELSE 'Discharged alive'
    END AS outcome_label
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE (LOWER(p.gender) IN ('m', 'male'))
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.edregtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  outcome_label,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  100.0 * SUM(CASE WHEN los_days <= 5.0 THEN 1 ELSE 0 END) / COUNT(*) AS pct_le_5_days
FROM filtered
GROUP BY outcome_label
ORDER BY outcome_label;