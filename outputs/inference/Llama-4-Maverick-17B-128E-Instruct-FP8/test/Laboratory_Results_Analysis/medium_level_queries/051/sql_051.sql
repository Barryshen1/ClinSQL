WITH 
-- Filter male patients aged 80-90
patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 80 AND 90
),

-- Identify ACS admissions
acs_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
  ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE (d.icd_version = 9 AND d.icd_code LIKE '410%') 
     OR (d.icd_version = 10 AND diag.long_title LIKE '%acute myocardial infarction%')
),

-- Get first hs-TnT measurement for ACS admissions
hs_tnt AS (
  SELECT l.hadm_id, 
         l.valuenum AS hs_tnt_value,
         ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
  ON l.itemid = dl.itemid
  WHERE dl.label LIKE '%Troponin T%' AND l.valuenum IS NOT NULL
),

-- Calculate hospital LOS and categorize hs-TnT
admissions_los AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los,
         CASE 
           WHEN hs.hs_tnt_value <= 14 THEN 'Normal'
           WHEN hs.hs_tnt_value <= 52 THEN 'Borderline'
           ELSE 'Myocardial Injury'
         END AS hs_tnt_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN hs_tnt hs ON a.hadm_id = hs.hadm_id AND hs.rn = 1
  WHERE a.hadm_id IN (SELECT hadm_id FROM acs_admissions)
)

-- Report counts, percentages, and mean LOS
SELECT 
  hs_tnt_category,
  COUNT(*) AS count,
  COUNT(*) * 100.0 / (SELECT COUNT(*) FROM admissions_los) AS percentage,
  AVG(los) AS mean_los
FROM admissions_los
GROUP BY hs_tnt_category
ORDER BY hs_tnt_category;