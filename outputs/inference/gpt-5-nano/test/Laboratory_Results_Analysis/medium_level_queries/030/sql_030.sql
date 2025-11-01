WITH
  -- Identify hs-TnT lab items (high-sensitivity troponin T)
  hs_items AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE LOWER(label) LIKE '%troponin%'
      AND (LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high-sensitivity%')
  ),

  -- AMI admissions for females aged 64-74
  ami_admissions AS (
    SELECT DISTINCT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON di.hadm_id = a.hadm_id AND di.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON p.subject_id = a.subject_id
    WHERE (LOWER(p.gender) IN ('f', 'female'))
      AND p.anchor_age BETWEEN 64 AND 74
      AND (
        (di.icd_version = 9 AND di.icd_code LIKE '410%')
        OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
      )
  ),

  -- hs-TnT lab events for those admissions
  hs_events AS (
    SELECT le.hadm_id, le.subject_id, le.charttime, le.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN hs_items AS hi ON le.itemid = hi.itemid
    JOIN ami_admissions AS aa ON aa.hadm_id = le.hadm_id
    WHERE le.valuenum IS NOT NULL
  ),

  -- First hs-TnT value per admission (index)
  first_hs AS (
    SELECT hadm_id, subject_id, charttime, valuenum,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM hs_events
  ),

  -- Categorize index hs-TnT value
  categorized AS (
    SELECT hadm_id, subject_id, valuenum,
           CASE
             WHEN valuenum <= 0.014 THEN 'Normal'
             WHEN valuenum <= 0.052 THEN 'Borderline'
             ELSE 'Myocardial Injury'
           END AS category
    FROM first_hs
    WHERE rn = 1
  ),

  -- Total admissions contributing to the denominator
  total AS (
    SELECT COUNT(*) AS total FROM categorized
  )

SELECT
  category,
  COUNT(*) AS n,
  ROUND(100.0 * COUNT(*) / t.total, 2) AS pct
FROM categorized
CROSS JOIN total AS t
GROUP BY category, t.total
ORDER BY category;