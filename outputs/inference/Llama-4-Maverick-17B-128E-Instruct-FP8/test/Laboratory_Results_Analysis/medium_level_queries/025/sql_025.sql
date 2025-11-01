WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 58 AND 68
),
relevant_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%myocardial infarction%' OR d_icd.long_title LIKE '%chest pain%'
),
troponin_t_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin T%'
),
first_troponin_t AS (
  SELECT lab.subject_id, lab.hadm_id, lab.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY lab.hadm_id ORDER BY lab.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  WHERE lab.itemid IN (SELECT itemid FROM troponin_t_itemid)
),
filtered_admissions AS (
  SELECT hadm_id
  FROM first_troponin_t
  WHERE rn = 1 AND valuenum > 0.01
)
SELECT 
  AVG(lab.valuenum) as mean,
  STDDEV(lab.valuenum) as std_dev,
  MIN(lab.valuenum) as min_val,
  MAX(lab.valuenum) as max_val
FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
JOIN troponin_t_itemid ON lab.itemid = troponin_t_itemid.itemid
WHERE lab.hadm_id IN (SELECT hadm_id FROM relevant_admissions)
  AND lab.hadm_id IN (SELECT hadm_id FROM filtered_admissions)
  AND lab.subject_id IN (SELECT subject_id FROM female_patients);