SELECT
  discharge_outcome,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  100.0 * COUNTIF(los_days <= 10) / COUNT(*) AS pct_leq_10_days
FROM (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 'In-hospital death'
      WHEN REGEXP_CONTAINS(LOWER(a.discharge_location), r'home') THEN 'Home'
      WHEN REGEXP_CONTAINS(LOWER(a.discharge_location), r'hospice') THEN 'Hospice'
      ELSE NULL
    END AS discharge_outcome,
    i.los / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND i.los IS NOT NULL
) AS t
WHERE discharge_outcome IS NOT NULL
GROUP BY discharge_outcome
ORDER BY discharge_outcome;