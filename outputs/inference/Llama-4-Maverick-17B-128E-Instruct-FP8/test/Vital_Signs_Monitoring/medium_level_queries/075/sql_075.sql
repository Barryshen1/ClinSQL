WITH patient_info AS (
  SELECT p.subject_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
),
icu_stays AS (
  SELECT i.stay_id, i.hadm_id, i.subject_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
mean_map AS (
  SELECT i.stay_id, AVG(c.valuenum) AS avg_map
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
  WHERE c.itemid = 220052 AND c.charttime BETWEEN i.intime AND i.outtime
  GROUP BY i.stay_id
),
stroke_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE (dicd.long_title LIKE '%stroke%' OR dicd.long_title LIKE '%cerebral infarction%') 
  AND (d.icd_version = 9 OR d.icd_version = 10)
),
categorized_map AS (
  SELECT 
    mm.stay_id,
    i.hadm_id,
    i.subject_id,
    CASE
      WHEN mm.avg_map < 65 THEN '<65'
      WHEN mm.avg_map >= 65 AND mm.avg_map < 75 THEN '65-74'
      WHEN mm.avg_map >= 75 AND mm.avg_map < 85 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM mean_map mm
  JOIN icu_stays i ON mm.stay_id = i.stay_id
)
SELECT 
  cm.map_category,
  COUNT(cm.stay_id) AS num_stays,
  COUNT(DISTINCT CASE WHEN sp.hadm_id IS NOT NULL THEN cm.hadm_id END) AS num_strokes,
  COUNT(DISTINCT CASE WHEN sp.hadm_id IS NOT NULL THEN cm.hadm_id END) / COUNT(DISTINCT cm.hadm_id) AS stroke_rate
FROM categorized_map cm
JOIN patient_info p ON cm.subject_id = p.subject_id
LEFT JOIN stroke_patients sp ON cm.hadm_id = sp.hadm_id
WHERE p.gender = 'M' AND p.anchor_age BETWEEN 56 AND 66
GROUP BY cm.map_category
ORDER BY cm.map_category;