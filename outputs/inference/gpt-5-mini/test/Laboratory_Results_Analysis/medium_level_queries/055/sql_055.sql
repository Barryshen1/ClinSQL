WITH troponin_items AS (
  -- identify candidate hs-TnT lab items by label / loinc heuristics
  SELECT itemid, label, loinc_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE (
    LOWER(label) LIKE '%troponin t%' OR
    LOWER(label) LIKE '%hs-tnt%' OR
    LOWER(label) LIKE '%high sensitivity troponin%' OR
    LOWER(label) LIKE '%high-sensitivity troponin%' OR
    (loinc_code IS NOT NULL AND LOWER(CAST(loinc_code AS STRING)) LIKE '%6598%')
  )
),

admissions_of_interest AS (
  -- admissions where any diagnosis contains 'myocardial infarction' or 'chest pain'
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (
    LOWER(d.long_title) LIKE '%myocardial infarction%' OR
    LOWER(d.long_title) LIKE '%acute myocardial infarction%' OR
    LOWER(d.long_title) LIKE '%chest pain%'
  )
),

eligible_admissions AS (
  -- apply patient-level filters (female, anchor_age 81-91)
  SELECT aoi.*
  FROM admissions_of_interest aoi
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON aoi.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),

index_hs_tnt_raw AS (
  -- find hs-TnT lab events for these admissions within 24 hours of admittime
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  JOIN eligible_admissions ea
    ON le.hadm_id = ea.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= ea.admittime
    AND le.charttime <= TIMESTAMP_ADD(ea.admittime, INTERVAL 24 HOUR)
),

index_hs_tnt AS (
  -- pick the first (earliest) hs-TnT per admission within the 24h window
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
  FROM index_hs_tnt_raw
)

SELECT
  category,
  COUNT(1) AS admission_count,
  ROUND(100.0 * COUNT(1) / SUM(COUNT(1)) OVER (), 2) AS pct_of_cohort,
  ROUND(AVG(TIMESTAMP_DIFF(ad.dischtime, ad.admittime, SECOND) / 86400.0), 2) AS mean_los_days
FROM (
  -- join the index troponin (first within 24h) to admission record
  SELECT
    ih.hadm_id,
    ih.valuenum,
    CASE
      WHEN ih.valuenum < 14 THEN 'normal (<14)'
      WHEN ih.valuenum >= 14 AND ih.valuenum < 52 THEN 'borderline (14-51.9)'
      WHEN ih.valuenum >= 52 THEN 'myocardial injury (>=52)'
      ELSE 'unknown'
    END AS category
  FROM index_hs_tnt ih
  WHERE ih.rn = 1
) t
JOIN eligible_admissions ad ON t.hadm_id = ad.hadm_id
GROUP BY category
ORDER BY
  CASE
    WHEN category LIKE 'normal%' THEN 1
    WHEN category LIKE 'borderline%' THEN 2
    WHEN category LIKE 'myocardial injury%' THEN 3
    ELSE 4
  END;