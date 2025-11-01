WITH acs_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND did.icd_version = 10
    AND (
      did.long_title LIKE '%acute coronary%'
      OR did.long_title LIKE '%myocardial infarction%'
      OR did.long_title LIKE '%unstable angina%'
      OR did.long_title LIKE '%acute ischemic heart disease%'
    )
),
troponin_first AS (
  SELECT 
    a.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) AS rn
  FROM acs_admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.labevents l ON a.hadm_id = l.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
),
troponin_categorized AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN valuenum < 0.01 THEN 'normal'
      WHEN valuenum BETWEEN 0.01 AND 0.03 THEN 'borderline'
      WHEN valuenum > 0.03 THEN 'elevated'
      ELSE NULL
    END AS category,
    valuenum
  FROM troponin_first
  WHERE rn = 1
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS percentage,
  ROUND(AVG(valuenum), 4) AS mean,
  ROUND(PERCENTILE_CONT(valuenum, 0.5), 4) AS median,
  ROUND(PERCENTILE_CONT(valuenum, 0.75) - PERCENTILE_CONT(valuenum, 0.25), 4) AS iqr
FROM troponin_categorized
WHERE category IS NOT NULL
GROUP BY category
ORDER BY category;