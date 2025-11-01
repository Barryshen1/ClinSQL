SELECT
  outcome,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS median_los,
  (COUNTIF(los <= 10) * 100.0 / COUNT(*)) AS percent_le10
FROM (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Death'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location = 'HOSPICE' THEN 'Hospice'
    END AS outcome,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 63 AND 73
    AND (a.hospital_expire_flag = 1 OR a.discharge_location IN ('HOME', 'HOSPICE'))
) AS subquery
GROUP BY outcome;