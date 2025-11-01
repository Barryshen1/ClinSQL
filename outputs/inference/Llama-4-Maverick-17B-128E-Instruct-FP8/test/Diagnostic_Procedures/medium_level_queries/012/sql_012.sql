WITH 
acs_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
  ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%acute coronary syndrome%' OR diag.long_title LIKE '%myocardial infarction%'
),

eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN acs_admissions acs ON a.hadm_id = acs.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 35 AND 45
),

los_categories AS (
  SELECT hadm_id,
         DATE_DIFF(dischtime, admittime, DAY) AS los,
         CASE 
           WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
           WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
           ELSE NULL
         END AS los_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM eligible_patients)
),

ultrasound_counts AS (
  SELECT c.hadm_id, COUNT(c.itemid) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` i ON c.itemid = i.itemid
  WHERE i.label LIKE '%echocardiogram%' OR i.label LIKE '%ultrasound%' 
  GROUP BY c.hadm_id
)

SELECT 
  l.los_category,
  COUNT(DISTINCT l.hadm_id) AS patient_count,
  AVG(u.ultrasound_count) AS mean_ultrasounds
FROM los_categories l
LEFT JOIN ultrasound_counts u ON l.hadm_id = u.hadm_id
WHERE l.los_category IS NOT NULL
GROUP BY l.los_category
ORDER BY l.los_category;