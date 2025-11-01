WITH medicine_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.services` s
    ON a.subject_id = s.subject_id
    AND a.hadm_id = s.hadm_id
    AND s.transfertime = a.admittime
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND s.curr_service = 'MEDICINE'
)
SELECT
  discharge_category,
  COUNT(*) AS n,
  ROUND(AVG(los), 2) AS mean_los_days,
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25_los_days,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los_days,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los_days,
  ROUND(100.0 * SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_le_10_days
FROM (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'DISCH HOME' THEN 'Discharge home'
      ELSE 'Discharge to facility'
    END AS discharge_category
  FROM medicine_admissions
  WHERE dischtime > admittime
)
GROUP BY discharge_category
ORDER BY n DESC;