WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE')
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
),

ultrasound_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE category = 'Imaging'
    AND (LOWER(label) LIKE '%echo%' 
         OR LOWER(label) LIKE '%ultrasound%' 
         OR LOWER(label) LIKE '%echocardiography%' 
         OR LOWER(label) LIKE '%doppler%' 
         OR LOWER(label) LIKE '%sonography%')
),

adm_ultrasounds AS (
  SELECT 
    c.hadm_id,
    CASE WHEN c.admission_type = 'EMERGENCY' THEN 'ED' ELSE 'Elective' END AS admission_type_group,
    CASE 
      WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    COUNT(DISTINCT ce.charttime) AS num_ultrasounds
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.stay_id = ce.stay_id
    AND ce.charttime >= c.admittime
    AND ce.charttime <= c.dischtime
  WHERE EXISTS (SELECT 1 FROM ultrasound_items ui WHERE ui.itemid = ce.itemid)
  GROUP BY c.hadm_id, admission_type_group, los_group
)

SELECT 
  admission_type_group,
  los_group,
  COUNT(DISTINCT hadm_id) AS num_admissions,
  AVG(num_ultrasounds) AS mean_ultrasounds,
  MIN(num_ultrasounds) AS min_ultrasounds,
  MAX(num_ultrasounds) AS max_ultrasounds
FROM adm_ultrasounds
GROUP BY admission_type_group, los_group
ORDER BY admission_type_group, los_group;