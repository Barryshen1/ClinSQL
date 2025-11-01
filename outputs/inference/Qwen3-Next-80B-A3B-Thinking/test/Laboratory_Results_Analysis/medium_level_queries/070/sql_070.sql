WITH troponin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
),
chest_pain_diagnoses AS (
  SELECT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%chest pain%'
),
male_90_100 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 90 AND 100
),
elevated_troponin AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_itemids ti ON le.itemid = ti.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  WHERE le.valuenum IS NOT NULL
    AND dl.ref_range_upper IS NOT NULL
    AND le.valuenum > dl.ref_range_upper
)
SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS p25,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY valuenum) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) AS p75,
  MAX(valuenum) - MIN(valuenum) AS range
FROM (
  SELECT et.valuenum
  FROM elevated_troponin et
  JOIN chest_pain_diagnoses cpd 
    ON et.subject_id = cpd.subject_id AND et.hadm_id = cpd.hadm_id
  JOIN male_90_100 m 
    ON et.subject_id = m.subject_id
  WHERE et.rn = 1
) AS filtered_values;