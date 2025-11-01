WITH chest_pain_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, p.anchor_age
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(d_icd.long_title) LIKE '%chest pain%'
),

hs_tnt_lab AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems di ON l.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%hs-tn%'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/L'  -- Ensure unit is ng/L (standard for hs-TnT in MIMIC-IV)
),

first_hs_tnt AS (
  SELECT 
    c.hadm_id,
    c.anchor_age,
    h.valuenum
  FROM chest_pain_admissions c
  JOIN hs_tnt_lab h ON c.hadm_id = h.hadm_id
  WHERE h.rn = 1
),

categorized_hs_tnt AS (
  SELECT 
    valuenum,
    CASE 
      WHEN valuenum < 14 THEN 'Normal'
      WHEN valuenum BETWEEN 14 AND 39 THEN 'Borderline'
      WHEN valuenum >= 40 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS category
  FROM first_hs_tnt
  WHERE valuenum IS NOT NULL
)

SELECT 
  category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(valuenum), 2) AS mean,
  ROUND(PERCENTILE_CONT(valuenum, 0.5) OVER (), 2) AS median,
  ROUND(PERCENTILE_CONT(valuenum, 0.25) OVER (), 2) AS q1,
  ROUND(PERCENTILE_CONT(valuenum, 0.75) OVER (), 2) AS q3,
  ROUND(PERCENTILE_CONT(valuenum, 0.75) OVER () - PERCENTILE_CONT(valuenum, 0.25) OVER (), 2) AS iqr
FROM categorized_hs_tnt
WHERE category IN ('Normal', 'Borderline', 'Myocardial Injury')
GROUP BY category, valuenum
ORDER BY category;