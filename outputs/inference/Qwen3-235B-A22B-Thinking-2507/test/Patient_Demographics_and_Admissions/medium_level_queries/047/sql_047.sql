WITH filtered_admissions AS (
  SELECT
    a.discharge_location,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
    AND a.dischtime IS NOT NULL
)
SELECT
  CASE 
    WHEN discharge_location = 'HOME' THEN 'home'
    WHEN discharge_location = 'DEAD/EXPIRED' THEN 'death'
    ELSE 'facility'
  END AS outcome_group,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los,
  (COUNTIF(los_days <= 5) * 100.0 / COUNT(*)) AS percentile_rank_5d
FROM filtered_admissions
WHERE age_at_admission BETWEEN 52 AND 62
GROUP BY outcome_group
ORDER BY 
  CASE outcome_group
    WHEN 'home' THEN 1
    WHEN 'facility' THEN 2
    WHEN 'death' THEN 3
  END;