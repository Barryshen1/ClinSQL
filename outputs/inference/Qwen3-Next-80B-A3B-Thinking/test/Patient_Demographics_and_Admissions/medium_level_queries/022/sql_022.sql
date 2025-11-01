SELECT
  discharge_category,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS p75,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY los) AS p90,
  SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_le_10
FROM (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN a.discharge_location = 'HOME' THEN 'home'
      WHEN a.discharge_location = 'HOSPICE' THEN 'hospice'
      ELSE NULL
    END AS discharge_category,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.admission_location LIKE '%TRANSFER FROM HOSPITAL%'
) subquery
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category;