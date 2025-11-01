WITH 
patient_icu AS (
  SELECT p.subject_id, p.gender, icu.stay_id, icu.hadm_id, 
         p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M' AND p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year BETWEEN 62 AND 72
),
heart_rate_itemid AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Heart Rate'
),
mean_heart_rate AS (
  SELECT ce.stay_id, AVG(ce.valuenum) AS mean_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN heart_rate_itemid hri ON ce.itemid = hri.itemid
  GROUP BY ce.stay_id
),
heart_rate_category AS (
  SELECT stay_id,
         CASE
           WHEN mean_hr < 60 THEN '<60'
           WHEN mean_hr BETWEEN 60 AND 99 THEN '60-99'
           WHEN mean_hr BETWEEN 100 AND 119 THEN '100-119'
           ELSE '>=120'
         END AS hr_category
  FROM mean_heart_rate
),
acute_mi AS (
  SELECT DISTINCT hadm_id, 1 AS acute_mi_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Acute myocardial infarction%' 
)
SELECT 
  hrc.hr_category,
  COUNT(DISTINCT pi.stay_id) AS count_stays,
  SAFE_DIVIDE(SUM(CASE WHEN ami.acute_mi_flag = 1 THEN 1 ELSE 0 END), COUNT(DISTINCT pi.stay_id)) * 100 AS percent_acute_mi
FROM patient_icu pi
JOIN heart_rate_category hrc ON pi.stay_id = hrc.stay_id
LEFT JOIN acute_mi ami ON pi.hadm_id = ami.hadm_id
GROUP BY hrc.hr_category
ORDER BY hrc.hr_category;