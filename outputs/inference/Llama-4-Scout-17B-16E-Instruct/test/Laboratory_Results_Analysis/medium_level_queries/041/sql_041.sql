WITH 
-- Identify hs-Troponin T itemid
troponin_t_item AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%hs-Troponin T%'
),

-- Filter patients and get initial hs-Troponin T values
patients_info AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    le.valuenum AS troponin_t_value
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON a.hadm_id = le.hadm_id
  JOIN troponin_t_item tti ON le.itemid = tti.itemid
  WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND a.admission_type = 'Elective'
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE di.hadm_id = a.hadm_id
    AND di.icd_code IN ('410', 'I24', 'I25')
  )
  AND le.charttime = (SELECT MIN(charttime) FROM `physionet-data.mimiciv_3_1_hosp.labevents` le2 WHERE le2.hadm_id = a.hadm_id AND le2.itemid = tti.itemid)
)

-- Calculate median and IQR
SELECT 
  APPROX_QUANTILES(troponin_t_value, 1000)[500] AS median,
  APPROX_QUANTILES(troponin_t_value, 1000)[250] AS q1,
  APPROX_QUANTILES(troponin_t_value, 1000)[750] AS q3
FROM patients_info
WHERE troponin_t_value > (
  SELECT APPROX_QUANTILES(valuenum, 1000)[990] 
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE itemid IN (SELECT itemid FROM troponin_t_item)
);