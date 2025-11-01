WITH sepsis_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (
      icd_code LIKE '038%' OR 
      icd_code IN ('99591', '99592', '1125', '5721', '7907')
    ))
    OR (icd_version = 10 AND (
      icd_code LIKE 'A40%' OR 
      icd_code LIKE 'A41%' OR 
      icd_code LIKE 'R65.2%'
    ))
),
male_sepsis_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN sepsis_admissions s
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'M'
),
first_platelet AS (
  SELECT 
    m.hadm_id,
    l.valuenum AS platelet_count,
    ROW_NUMBER() OVER (
      PARTITION BY m.hadm_id 
      ORDER BY l.charttime
    ) AS rn
  FROM male_sepsis_admissions m
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON m.hadm_id = l.hadm_id
  WHERE 
    l.itemid = 51265  -- Platelets lab itemid
    AND l.charttime >= m.admittime
    AND l.charttime <= m.admittime + INTERVAL '24' HOUR
    AND l.valuenum IS NOT NULL
)
SELECT 
  STDDEV(platelet_count) AS sd_platelet_count
FROM first_platelet
WHERE rn = 1;