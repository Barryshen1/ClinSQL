WITH 
-- Filter patients of interest and relevant data
patients_of_interest AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 70 AND 80
),

icu_stays AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    patients_of_interest p ON i.subject_id = p.subject_id
),

max_sbp AS (
  SELECT 
    ic.subject_id, 
    ic.hadm_id, 
    ic.stay_id,
    MAX(c.valuenum) AS max_sbp_value
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN 
    icu_stays ic ON c.subject_id = ic.subject_id AND c.hadm_id = ic.hadm_id AND c.stay_id = ic.stay_id
  WHERE 
    c.itemid = 220050 
    AND c.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 1 DAY)
  GROUP BY 
    ic.subject_id, 
    ic.hadm_id, 
    ic.stay_id
),

sbp_categories AS (
  SELECT 
    subject_id, 
    hadm_id,
    stay_id,
    max_sbp_value,
    CASE 
      WHEN max_sbp_value < 130 THEN '<130'
      WHEN max_sbp_value BETWEEN 130 AND 139 THEN '130-139'
      WHEN max_sbp_value BETWEEN 140 AND 159 THEN '140-159'
      ELSE '≥160'
    END AS sbp_category
  FROM 
    max_sbp
),

stroke_diagnoses AS (
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` i ON d.icd_code = i.icd_code AND d.icd_version = i.icd_version
  WHERE 
    i.long_title LIKE '%Stroke%' 
    OR i.long_title LIKE '%Cerebrovascular%'
)

-- Final calculation
SELECT 
  sbp_category,
  COUNT(DISTINCT CASE WHEN sd.hadm_id IS NOT NULL THEN sbp.subject_id END) AS stroke_count,
  COUNT(DISTINCT sbp.subject_id) AS total_patients,
  COUNT(DISTINCT CASE WHEN sd.hadm_id IS NOT NULL THEN sbp.subject_id END) * 100.0 / COUNT(DISTINCT sbp.subject_id) AS stroke_rate,
  COUNT(DISTINCT sbp.subject_id) * 100.0 / SUM(COUNT(DISTINCT sbp.subject_id)) OVER () AS percentage
FROM 
  sbp_categories sbp
  LEFT JOIN stroke_diagnoses sd ON sbp.subject_id = sd.subject_id AND sbp.hadm_id = sd.hadm_id
GROUP BY 
  sbp_category
ORDER BY 
  sbp_category;