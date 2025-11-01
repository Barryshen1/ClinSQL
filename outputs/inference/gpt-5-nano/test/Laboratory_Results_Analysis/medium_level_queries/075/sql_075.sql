WITH chest_ami_admissions AS (
  -- Admissions with chest pain or acute MI (case-insensitive)
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%myocardial infarction%'
     OR LOWER(dd.long_title) LIKE '%chest pain%'
),
troponin_lab AS (
  SELECT 
     ca.subject_id,
     ca.hadm_id,
     le.charttime,
     le.valuenum,
     LOWER(le.valueuom) AS unit
  FROM chest_ami_admissions ca
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ca.subject_id = le.subject_id AND ca.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dil
    ON le.itemid = dil.itemid
  WHERE LOWER(dil.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
),
troponin_ranked AS (
  SELECT
     subject_id,
     hadm_id,
     charttime,
     valuenum,
     unit,
     ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM troponin_lab
),
initial_troponin AS (
  SELECT
     subject_id,
     hadm_id,
     charttime,
     valuenum,
     unit,
     CASE
       WHEN unit IN ('ng/l','ng_per_l','ng per_l','ng per liter') THEN
         CASE
           WHEN valuenum <= 14 THEN 'normal'
           WHEN valuenum <= 40 THEN 'borderline'
           ELSE 'elevated'
         END
       WHEN unit IN ('ng/ml','ng_per_ml','ng per ml') THEN
         CASE
           WHEN valuenum <= 0.014 THEN 'normal'
           WHEN valuenum <= 0.04 THEN 'borderline'
           ELSE 'elevated'
         END
       ELSE NULL
     END AS category
  FROM troponin_ranked
  WHERE rn = 1
    AND (
        (unit IN ('ng/l','ng_per_l','ng per_l','ng per liter') ) OR
        (unit IN ('ng/ml','ng_per_ml','ng per ml') )
    )
),
cohort AS (
  SELECT it.subject_id,
         it.hadm_id,
         it.charttime,
         it.valuenum,
         it.unit,
         it.category
  FROM initial_troponin it
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON it.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 41 AND 51
)
SELECT
  category,
  COUNT(*) AS n,
  100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS pct,
  AVG(valuenum) AS mean_troponin,
  MAX(quantiles)[OFFSET(50)] AS median_troponin,
  (MAX(quantiles)[OFFSET(75)] - MAX(quantiles)[OFFSET(25)]) AS iqr
FROM (
  SELECT category,
         valuenum,
         APPROX_QUANTILES(valuenum, 100) OVER (PARTITION BY category) AS quantiles
  FROM cohort
  WHERE category IS NOT NULL
)
GROUP BY category
ORDER BY category;