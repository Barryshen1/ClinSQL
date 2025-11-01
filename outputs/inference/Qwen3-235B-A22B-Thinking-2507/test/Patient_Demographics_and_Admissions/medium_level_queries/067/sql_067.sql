WITH first_service AS (
  SELECT 
    hadm_id,
    curr_service
  FROM (
    SELECT 
      hadm_id,
      curr_service,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.services`
  )
  WHERE rn = 1 AND curr_service = 'MED'
),

base_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN first_service fs
    ON a.hadm_id = fs.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
    AND a.dischtime IS NOT NULL
),

filtered_admissions AS (
  SELECT 
    hadm_id,
    los,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location LIKE 'HOSPICE%' THEN 'hospice'
      WHEN discharge_location = 'HOME' THEN 'home'
      ELSE NULL 
    END AS discharge_category
  FROM base_admissions
  WHERE 
    hospital_expire_flag = 1 OR 
    discharge_location LIKE 'HOSPICE%' OR 
    discharge_location = 'HOME'
)

SELECT 
  discharge_category,
  ROUND(COUNT(CASE WHEN los >= 7 THEN 1 END) * 1.0 / COUNT(*), 4) AS prop_los_ge7,
  ROUND(COUNT(CASE WHEN los >= 14 THEN 1 END) * 1.0 / COUNT(*), 4) AS prop_los_ge14,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS los_75th_percentile
FROM filtered_admissions
GROUP BY discharge_category
ORDER BY discharge_category;