WITH troponin_items AS (
  -- permissive selection of troponin lab itemids; adjust/replace with exact LOINC/itemids if desired
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE (
    LOWER(label) LIKE '%troponin%' 
    OR LOWER(label) LIKE '%tnt%' 
    OR LOWER(label) LIKE '%hs troponin%' 
    OR LOWER(label) LIKE '%high sensitivity troponin%' 
    OR LOWER(label) LIKE '%troponin t%'
  )
),
chest_pain_adms AS (
  -- admissions for males aged 39-49 with primary dx containing "chest pain"
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dic
    ON a.hadm_id = dic.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddesc
    ON dic.icd_code = ddesc.icd_code
    AND dic.icd_version = ddesc.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND dic.seq_num = 1  -- primary diagnosis
    AND LOWER(ddesc.long_title) LIKE '%chest pain%'
),
first_troponin AS (
  -- earliest troponin per admission (on/after admittime), numeric values only
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  JOIN chest_pain_adms ca
    ON le.hadm_id = ca.hadm_id
    AND le.charttime >= ca.admittime
  WHERE le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime, le.storetime) = 1
),
categorized AS (
  -- categorize using chosen thresholds (adjust thresholds if needed)
  SELECT
    ft.hadm_id,
    ft.subject_id,
    ft.charttime,
    ft.valuenum,
    CASE
      WHEN ft.valuenum <= 14 THEN 'normal'                     -- <=14 ng/L (commonly 99th percentile)
      WHEN ft.valuenum > 14 AND ft.valuenum <= 50 THEN 'borderline'  -- >14 to 50
      WHEN ft.valuenum > 50 THEN 'myocardial injury'           -- >50
      ELSE 'unknown'
    END AS category
  FROM first_troponin ft
),
stats_by_cat AS (
  -- compute counts, percentages, mean, and approximate quantiles per category
  SELECT
    category,
    COUNT(*) AS n,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent_of_measured,
    ROUND(AVG(valuenum), 2) AS mean_hsTnT,
    (APPROX_QUANTILES(valuenum, 4))[OFFSET(1)] AS p25_approx,
    (APPROX_QUANTILES(valuenum, 4))[OFFSET(2)] AS median_approx,
    (APPROX_QUANTILES(valuenum, 4))[OFFSET(3)] AS p75_approx
  FROM categorized
  GROUP BY category
)
SELECT
  category,
  n,
  percent_of_measured,
  mean_hsTnT,
  median_approx AS median_hsTnT,
  p25_approx AS p25_hsTnT,
  p75_approx AS p75_hsTnT
FROM stats_by_cat
ORDER BY
  -- order by clinical severity
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'myocardial injury' THEN 3
    ELSE 4
  END;