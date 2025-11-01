WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 41 AND 51
),

icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN female_patients f ON i.subject_id = f.subject_id
),

stroke_diagnosis AS (
  SELECT hadm_id, MAX(CASE 
    WHEN (icd_version = 9 AND icd_code BETWEEN '430' AND '438') 
      OR (icd_version = 10 AND icd_code BETWEEN 'I60' AND 'I69') 
    THEN 1 ELSE 0 END) AS has_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

map_measurements AS (
  SELECT 
    c.subject_id,
    CASE 
      WHEN c.valuenum < 65 THEN '<65'
      WHEN c.valuenum BETWEEN 65 AND 74 THEN '65-74'
      WHEN c.valuenum BETWEEN 75 AND 84 THEN '75-84'
      ELSE '≥85'
    END AS map_category,
    s.has_stroke
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN icu_stays i ON c.stay_id = i.stay_id
  LEFT JOIN stroke_diagnosis s ON i.hadm_id = s.hadm_id
  WHERE c.itemid = 52
    AND c.valuenum IS NOT NULL
)

SELECT 
  map_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN has_stroke = 1 THEN subject_id END) AS stroke_count,
  COUNT(DISTINCT CASE WHEN has_stroke = 1 THEN subject_id END) / COUNT(DISTINCT subject_id) AS stroke_rate
FROM map_measurements
GROUP BY map_category
ORDER BY map_category;