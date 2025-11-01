SELECT
  discharge_disposition,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(los, 0.5) WITHIN GROUP (ORDER BY los) AS median_los,
  PERCENTILE_CONT(los, 0.75) WITHIN GROUP (ORDER BY los) AS p75_los,
  PERCENTILE_CONT(los, 0.90) WITHIN GROUP (ORDER BY los) AS p90_los,
  (SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percentile_rank_10_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
      WHEN a.discharge_location LIKE 'HOME%' THEN 'Discharged home'
      ELSE NULL
    END AS discharge_disposition
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
    AND a.admission_location LIKE 'EMERGENCY ROOM%'
) filtered
WHERE discharge_disposition IS NOT NULL
GROUP BY discharge_disposition;