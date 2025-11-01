SELECT
  discharge_category,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS p75_los,
  PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY los) AS p90_los,
  COUNTIF(los < 5) * 100.0 / COUNT(*) AS percent_less_than_5
FROM (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'DEATH'
      WHEN a.discharge_location = 'HOME' THEN 'HOME'
      WHEN a.discharge_location = 'HOSPICE' THEN 'HOSPICE'
    END AS discharge_category,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 89 AND 99
    AND a.admission_type = 'ELECTIVE'
    AND (a.hospital_expire_flag = 1 OR a.discharge_location IN ('HOME', 'HOSPICE'))
) subquery
GROUP BY discharge_category;