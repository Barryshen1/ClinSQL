WITH chest_pain_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
    AND d.seq_num = 1
    AND LOWER(d_icd.long_title) LIKE '%chest pain%'
),
initial_hstnt AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  INNER JOIN chest_pain_admissions cpa ON le.hadm_id = cpa.hadm_id
  WHERE LOWER(dl.label) LIKE '%high sensitivity%troponin%t%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
)
SELECT
  CASE 
    WHEN valuenum < 14 THEN 'normal'
    WHEN valuenum BETWEEN 14 AND 39 THEN 'borderline'
    WHEN valuenum >= 40 THEN 'myocardial injury'
  END AS category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM initial_hstnt
WHERE rn = 1
GROUP BY category
ORDER BY category;