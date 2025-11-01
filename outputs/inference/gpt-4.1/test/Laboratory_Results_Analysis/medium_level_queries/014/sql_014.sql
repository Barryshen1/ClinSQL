WITH acs_icd_codes AS (
  -- List of ACS ICD codes (ICD-9 and ICD-10)
  SELECT '410' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '411', 9 UNION ALL
  SELECT '413', 9 UNION ALL
  SELECT 'I20', 10 UNION ALL
  SELECT 'I21', 10 UNION ALL
  SELECT 'I22', 10 UNION ALL
  SELECT 'I24', 10
),
acs_admissions AS (
  -- Admissions for male patients aged 79-89 with ACS
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON adm.subject_id = pat.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON adm.hadm_id = diag.hadm_id
  JOIN acs_icd_codes acs
    ON diag.icd_code = acs.icd_code AND diag.icd_version = acs.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 79 AND 89
),
troponin_t_items AS (
  -- Find itemids for Troponin T
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%troponin t%'
),
initial_troponin_t AS (
  -- For each ACS admission, get the first Troponin T value
  SELECT
    la.subject_id,
    la.hadm_id,
    la.charttime,
    la.valuenum
  FROM physionet-data.mimiciv_3_1_hosp.labevents la
  JOIN troponin_t_items tti
    ON la.itemid = tti.itemid
  JOIN acs_admissions acs
    ON la.subject_id = acs.subject_id AND la.hadm_id = acs.hadm_id
  WHERE la.valuenum IS NOT NULL
    -- Only keep the earliest Troponin T per admission
    AND la.charttime = (
      SELECT MIN(charttime)
      FROM physionet-data.mimiciv_3_1_hosp.labevents la2
      WHERE la2.subject_id = la.subject_id
        AND la2.hadm_id = la.hadm_id
        AND la2.itemid = la.itemid
        AND la2.valuenum IS NOT NULL
    )
),
categorized_troponin AS (
  -- Categorize initial Troponin T
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum < 0.01 THEN 'Normal'
      WHEN valuenum >= 0.01 AND valuenum <= 0.03 THEN 'Borderline'
      WHEN valuenum > 0.03 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM initial_troponin_t
)
SELECT
  troponin_category AS category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM categorized_troponin
WHERE troponin_category IN ('Normal', 'Borderline', 'Elevated')
GROUP BY troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END
;