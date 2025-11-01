SELECT
  outcome_category,
  PERCENTILE_CONT(los, 0.5) AS p50,
  PERCENTILE_CONT(los, 0.75) AS p75,
  PERCENTILE_CONT(los, 0.90) AS p90,
  PERCENTILE_CONT(los, 0.95) AS p95,
  SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_le_7
FROM (
  SELECT
    i.los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location = 'HOSPICE' THEN 'hospice'
      WHEN a.discharge_location = 'HOME' THEN 'home'
      ELSE NULL
    END AS outcome_category
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 40 AND 50
) subquery
WHERE outcome_category IS NOT NULL
GROUP BY outcome_category;