WITH chest_pain_admissions AS (
  SELECT DISTINCT p.subject_id, p.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON d.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND LOWER(d_icd.long_title) LIKE '%chest pain%'
),
troponin_i_events AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin i%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0.04  -- elevated threshold
),
first_elevated_troponin AS (
  SELECT hadm_id, valuenum
  FROM troponin_i_events
  WHERE rn = 1
)
SELECT 
  PERCENTILE_CONT(valuenum, 0.25) AS p25,
  PERCENTILE_CONT(valuenum, 0.50) AS p50,
  PERCENTILE_CONT(valuenum, 0.75) AS p75,
  MAX(valuenum) - MIN(valuenum) AS range
FROM first_elevated_troponin
JOIN chest_pain_admissions cpa
  ON first_elevated_troponin.hadm_id = cpa.hadm_id;