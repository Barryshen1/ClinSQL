WITH chest_pain_icds AS (
  -- ICD-9 and ICD-10 codes for chest pain
  SELECT '78650' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '78651', 9 UNION ALL
  SELECT '78652', 9 UNION ALL
  SELECT '78659', 9 UNION ALL
  SELECT 'R079', 10 UNION ALL
  SELECT 'R071', 10 UNION ALL
  SELECT 'R072', 10
),
hs_tnt_items AS (
  -- Find itemids for hs-TnT in d_labitems
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND (LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high%' OR LOWER(label) LIKE '%sens%')
),
cohort AS (
  -- Female patients age 87-97 with chest pain diagnosis
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN chest_pain_icds icd
    ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 87 AND 97
),
index_hs_tnt AS (
  -- Get first hs-TnT value per admission
  SELECT
    c.subject_id,
    c.hadm_id,
    l.charttime,
    l.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  JOIN hs_tnt_items h
    ON l.itemid = h.itemid
  WHERE l.valuenum IS NOT NULL
),
first_hs_tnt AS (
  -- For each admission, select the earliest hs-TnT value
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS index_charttime
  FROM index_hs_tnt
  GROUP BY subject_id, hadm_id
),
index_hs_tnt_value AS (
  -- Get the value for the earliest hs-TnT per admission
  SELECT
    i.subject_id,
    i.hadm_id,
    i.charttime,
    i.valuenum
  FROM index_hs_tnt i
  JOIN first_hs_tnt f
    ON i.subject_id = f.subject_id
    AND i.hadm_id = f.hadm_id
    AND i.charttime = f.index_charttime
),
categorized AS (
  -- Categorize hs-TnT values
  SELECT
    *,
    CASE
      WHEN valuenum <= 0.04 THEN 'Normal'
      WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'Borderline'
      WHEN valuenum > 0.1 THEN 'Injury'
      ELSE 'Unknown'
    END AS tnt_category
  FROM index_hs_tnt_value
)
SELECT
  tnt_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(valuenum), 4) AS mean,
  ROUND(APPROX_QUANTILES(valuenum, 2)[OFFSET(1)], 4) AS median,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(1)], 4) AS iqr_25,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(3)], 4) AS iqr_75
FROM categorized
WHERE tnt_category IN ('Normal', 'Borderline', 'Injury')
GROUP BY tnt_category
ORDER BY
  CASE tnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Injury' THEN 3
    ELSE 4
  END
;