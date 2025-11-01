WITH first_service AS (
  SELECT 
    hadm_id,
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60.0) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN first_service fs
    ON a.hadm_id = fs.hadm_id
  WHERE fs.rn = 1
    AND fs.curr_service = 'MED'
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
),
categorized AS (
  SELECT 
    hadm_id,
    los,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'HOME' THEN 'discharge home'
      ELSE 'facility'
    END AS discharge_category
  FROM filtered_admissions
)
SELECT 
  discharge_category,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(250)] AS p25_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS p50_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(900)] AS p90_los,
  COUNTIF(los <= 10) * 100.0 / COUNT(*) AS percent_los_le_10
FROM categorized
GROUP BY discharge_category
ORDER BY 
  CASE discharge_category
    WHEN 'discharge home' THEN 1
    WHEN 'facility' THEN 2
    WHEN 'in-hospital death' THEN 3
  END;