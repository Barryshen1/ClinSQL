WITH patient_data AS (
  SELECT 
    CASE 
      WHEN a.discharge_location IN ('HOME HEALTH CARE') THEN 'home'
      WHEN a.discharge_location IN ('REHAB', 'REHABILITATION', 'SNF', 'SKILLED NURSING FACILITY', 'LONG TERM CARE', 'OTHER FACILITY') THEN 'facility'
      ELSE NULL
    END AS discharge_category,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN DATE_DIFF(a.deathtime, a.admittime, DAY)
      ELSE DATE_DIFF(a.dischtime, a.admittime, DAY)
    END AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN (
    SELECT DISTINCT hadm_id, subject_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i
    ON a.hadm_id = i.hadm_id AND a.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND DATE_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 38 AND 48
    AND (a.hospital_expire_flag = 1 OR a.dischtime IS NOT NULL)
    AND a.discharge_location IS NOT NULL
)
SELECT 
  discharge_category,
  AVG(los_days) AS mean_los,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_days) AS median_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS p75_los,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY los_days) AS p90_los
FROM patient_data
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category;