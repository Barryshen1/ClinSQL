WITH qualifying_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND (
      did.long_title LIKE '%chest pain%'
      OR did.long_title LIKE '%acute myocardial infarction%'
      OR d.icd_code LIKE 'I21%'
      OR d.icd_code LIKE 'I22%'
      OR d.icd_code LIKE 'I23%'
    )
),
first_troponin_t AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON le.itemid = dl.itemid
  WHERE dl.label = 'Troponin T'
    AND le.valuenum IS NOT NULL
    AND le.hadm_id IN (SELECT hadm_id FROM qualifying_admissions)
),
overall_stats AS (
  SELECT
    APPROX_QUANTILES(ft.valuenum, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(ft.valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(ft.valuenum, 100)[OFFSET(25)] AS iqr
  FROM first_troponin_t ft
  WHERE ft.rn = 1
),
grouped_stats AS (
  SELECT
    CASE 
      WHEN ft.valuenum <= 0.04 THEN 'normal'
      WHEN ft.valuenum <= 0.1 THEN 'borderline'
      ELSE 'elevated'
    END AS category,
    COUNT(*) AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
    ROUND(AVG(ft.valuenum), 4) AS mean
  FROM first_troponin_t ft
  WHERE ft.rn = 1
  GROUP BY category
)
SELECT
  gs.category,
  gs.count,
  gs.percentage,
  gs.mean,
  os.median,
  os.iqr
FROM grouped_stats gs
CROSS JOIN overall_stats os
ORDER BY gs.category;