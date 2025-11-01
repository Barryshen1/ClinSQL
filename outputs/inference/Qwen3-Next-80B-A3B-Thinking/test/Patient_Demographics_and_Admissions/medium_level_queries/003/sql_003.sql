SELECT
  `group`,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS p75,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY los) AS p90,
  SUM(CASE WHEN los <= 14 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_le_14
FROM (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'Home' THEN 'Home'
      WHEN discharge_location = 'Hospice' THEN 'Hospice'
    END AS `group`,
    DATE_DIFF(dischtime, admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 80 AND 90
    AND a.admission_type NOT IN ('emergency', 'trauma')
    AND (a.discharge_location IN ('Home', 'Hospice') OR a.hospital_expire_flag = 1)
) subquery
GROUP BY `group`;