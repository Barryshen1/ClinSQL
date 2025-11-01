WITH chest_pain_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(dd.long_title) LIKE '%chest pain%'
    AND LOWER(p.gender) IN ('m','male')
    AND CAST(p.anchor_age AS INT64) BETWEEN 61 AND 71
),

initial_hstn AS (
  SELECT le.hadm_id, le.subject_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE le.hadm_id IN (SELECT hadm_id FROM chest_pain_admissions)
    AND (LOWER(dli.label) LIKE '%hs-tn%' OR LOWER(dli.label) LIKE '%troponin%')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
),

category_counts AS (
  SELECT
    CASE
      WHEN ih.valuenum < 14 THEN 'normal'
      WHEN ih.valuenum >= 14 AND ih.valuenum < 52 THEN 'borderline'
      WHEN ih.valuenum >= 52 THEN 'myocardial_injury'
    END AS category,
    COUNT(*) AS count
  FROM initial_hstn ih
  -- initial_hstn already restricted to chest-pain admissions; this join is just to keep scope explicit
  JOIN chest_pain_admissions cpa ON ih.hadm_id = cpa.hadm_id
  WHERE ih.valuenum IS NOT NULL
  GROUP BY category
),

all_categories AS (
  SELECT 'normal' AS category UNION ALL
  SELECT 'borderline' UNION ALL
  SELECT 'myocardial_injury' AS category
),

tot AS (
  SELECT SUM(count) AS total FROM category_counts
)

SELECT a.category,
       COALESCE(cc.count, 0) AS count,
       ROUND(100.0 * COALESCE(cc.count, 0) / t.total, 2) AS percent
FROM all_categories a
LEFT JOIN category_counts cc ON cc.category = a.category
CROSS JOIN tot t
ORDER BY a.category;