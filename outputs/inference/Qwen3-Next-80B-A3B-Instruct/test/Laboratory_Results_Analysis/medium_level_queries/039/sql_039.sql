WITH chest_pain_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE '%chest pain%'
),
filtered_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
),
hs_tnt_lab AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%hs-tn%' 
    OR LOWER(dl.label) LIKE '%high sensitivity troponin t%'
    OR LOWER(dl.label) LIKE '%hs troponin t%'
    OR LOWER(dl.label) LIKE '%high sensitivity troponin%'
    OR LOWER(dl.label) LIKE '%troponin t hs%'
    OR LOWER(dl.label) LIKE '%troponin t high sensitivity%'
    OR LOWER(dl.label) LIKE '%hs-tnt%'
    OR LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum >= 0
),
first_hs_tnt AS (
  SELECT 
    h.hadm_id,
    h.valuenum
  FROM hs_tnt_lab h
  WHERE h.rn = 1
),
final_data AS (
  SELECT 
    fp.subject_id,
    fp.anchor_age,
    fht.valuenum,
    CASE 
      WHEN fht.valuenum <= 0.04 THEN 'Normal'
      WHEN fht.valuenum > 0.04 AND fht.valuenum <= 0.1 THEN 'Borderline'
      WHEN fht.valuenum > 0.1 THEN 'Injury'
    END AS tnt_category
  FROM filtered_patients fp
  JOIN chest_pain_admissions cpa ON fp.subject_id = cpa.subject_id
  JOIN first_hs_tnt fht ON cpa.hadm_id = fht.hadm_id
  WHERE fht.valuenum IS NOT NULL
)
SELECT 
  tnt_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(valuenum), 4) AS mean,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(2)], 4) AS median,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(1)], 4) AS q1,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(3)], 4) AS q3
FROM final_data
WHERE tnt_category IS NOT NULL
GROUP BY tnt_category
ORDER BY 
  CASE tnt_category 
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Injury' THEN 3
  END;