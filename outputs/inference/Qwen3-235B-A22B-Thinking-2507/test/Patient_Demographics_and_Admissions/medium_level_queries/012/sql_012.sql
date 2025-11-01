WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 75 AND 85
),
categorized AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'HOME' THEN 'discharged home'
      WHEN discharge_location IN (
        'SKILLED NURSING FACILITY', 
        'NURSING HOME', 
        'ASSISTED LIVING', 
        'INTERMEDIATE CARE', 
        'REHAB/DISTINCT PART HOSP', 
        'FEDERALLY QUALIFIED HEALTH CTR', 
        'INPATIENT HOSPICE', 
        'PSYCH HOSPITAL', 
        'REHAB HOSPITAL', 
        'CHRONIC DISABILITY INSTITUTION', 
        'FREESTANDING RENAL DIALYSIS CTR'
      ) THEN 'discharged to facility'
      ELSE NULL
    END AS discharge_category
  FROM filtered_admissions
)
SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN dischtime >= admittime + INTERVAL '7' DAY THEN 1 ELSE 0 END) AS count_los_ge7,
  SUM(CASE WHEN dischtime <= admittime + INTERVAL '7' DAY THEN 1 ELSE 0 END) AS count_los_le7,
  ROUND(SUM(CASE WHEN dischtime >= admittime + INTERVAL '7' DAY THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 4) AS proportion_los_ge7,
  ROUND(SUM(CASE WHEN dischtime <= admittime + INTERVAL '7' DAY THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS percentile_rank_7_percent
FROM categorized
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category
ORDER BY discharge_category;