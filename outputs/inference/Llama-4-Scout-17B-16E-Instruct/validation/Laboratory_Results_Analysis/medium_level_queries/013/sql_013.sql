WITH 
-- Identify hs-TnT lab item
hs_tnt_item AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%hs-TnT%'
),

-- Select relevant patients and admissions
patients_admissions AS (
  SELECT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 50 AND 60
  AND a.admission_type IN ('CHEST PAIN', 'ACUTE MYOCARDIAL INFARCTION')
),

-- Select initial hs-TnT levels
hs_tnt_levels AS (
  SELECT ha.subject_id, ha.hadm_id, le.valuenum
  FROM patients_admissions ha
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON ha.hadm_id = le.hadm_id
  JOIN hs_tnt_item hti ON le.itemid = hti.itemid
  WHERE le.charttime = (SELECT MIN(charttime) FROM `physionet-data.mimiciv_3_1_hosp.labevents` le2 WHERE le2.hadm_id = ha.hadm_id AND le2.itemid = hti.itemid)
  AND le.valuenum > 0.014
)

-- Calculate statistics
SELECT 
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(valuenum) AS mean_hs_tnt,
  APPROX_QUANTILES(valuenum, 1000)[OFFSET(500)] AS median_hs_tnt,
  APPROX_QUANTILES(valuenum, 1000)[OFFSET(250)] AS q1_hs_tnt,
  APPROX_QUANTILES(valuenum, 1000)[OFFSET(750)] AS q3_hs_tnt
FROM hs_tnt_levels;