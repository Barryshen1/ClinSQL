WITH troponin_items AS (
  -- pick Troponin T items by label (some datasets do not expose a loinc_code column)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%troponin-t%'
),
cohort_admissions AS (
  -- admissions for male patients age 41-51 with chest pain or AMI diagnosis
  SELECT DISTINCT a.hadm_id,
         a.subject_id,
         a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    -- simple text match for chest pain / myocardial infarction in long_title
    AND (
          LOWER(dicd.long_title) LIKE '%chest pain%'
       OR LOWER(dicd.long_title) LIKE '%myocardial infarction%'
       OR LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
    )
),
first_troponin_per_adm AS (
  -- find earliest troponin charttime per admission (hadm_id)
  SELECT le.hadm_id,
         MIN(le.charttime) AS first_trop_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  JOIN cohort_admissions ca
    ON le.hadm_id = ca.hadm_id
  -- ensure the troponin occurred during the admission (on/after admittime)
  WHERE le.charttime >= ca.admittime
  GROUP BY le.hadm_id
),
initial_troponin AS (
  -- get the troponin value and reference range at the first measurement time
  SELECT ca.hadm_id,
         ca.subject_id,
         le.valuenum,
         le.valueuom,
         le.ref_range_lower,
         le.ref_range_upper,
         le.charttime
  FROM first_troponin_per_adm f
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = f.hadm_id
   AND le.charttime = f.first_trop_charttime
  JOIN cohort_admissions ca
    ON le.hadm_id = ca.hadm_id
  -- exclude non-numeric valuenum (we handle numeric summaries only)
  WHERE le.valuenum IS NOT NULL
),
categorized_troponin AS (
  -- categorize relative to the local reference upper limit.
  -- Note: if ref_range_upper is NULL we label 'unknown'.
  SELECT it.*,
    CASE
      WHEN it.ref_range_upper IS NULL THEN 'unknown'
      WHEN it.valuenum <= it.ref_range_upper THEN 'normal'
      WHEN it.valuenum > it.ref_range_upper
           AND it.valuenum <= (it.ref_range_upper * 2) THEN 'borderline'
      WHEN it.valuenum > (it.ref_range_upper * 2) THEN 'elevated'
      ELSE 'unknown'
    END AS trop_category
  FROM initial_troponin it
)

-- Aggregate per category, compute quantiles as an array, then unpack
SELECT
  trop_category AS troponin_category,
  n_admissions,
  ROUND(100.0 * n_admissions / total_categorized, 2) AS pct_of_cohort,
  ROUND(mean_valuenum, 4) AS mean_valuenum,
  quantiles[OFFSET(1)] AS approx_q1,
  quantiles[OFFSET(2)] AS approx_median,
  quantiles[OFFSET(3)] AS approx_q3,
  ROUND(quantiles[OFFSET(3)] - quantiles[OFFSET(1)], 4) AS approx_IQR,
  units_present
FROM (
  SELECT
    ct.trop_category,
    COUNT(*) AS n_admissions,
    AVG(ct.valuenum) AS mean_valuenum,
    APPROX_QUANTILES(ct.valuenum, 4) AS quantiles, -- returns array [min, Q1, median, Q3, max]
    ARRAY_AGG(DISTINCT ct.valueuom IGNORE NULLS) AS units_present
  FROM categorized_troponin ct
  WHERE ct.trop_category IN ('normal','borderline','elevated')
  GROUP BY ct.trop_category
) agg
CROSS JOIN (
  -- explicit total for categories considered (exclude 'unknown')
  SELECT COUNT(*) AS total_categorized
  FROM categorized_troponin
  WHERE trop_category IN ('normal','borderline','elevated')
) totals
ORDER BY
  CASE troponin_category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
    ELSE 4
  END;