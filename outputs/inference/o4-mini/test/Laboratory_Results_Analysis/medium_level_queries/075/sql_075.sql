WITH cohort AS (
  -- 1. define male patients age 41-51 with chest pain or AMI
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND (
      LOWER(dd.long_title) LIKE '%chest pain%'
      OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
    )
),
troponin_items AS (
  -- 2. find all itemids for Troponin T
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
initial_troponin AS (
  -- 3. get the initial (earliest) Troponin T lab per admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    le.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN troponin_items AS ti
    ON le.itemid = ti.itemid
  JOIN cohort AS c
    ON le.hadm_id = c.hadm_id
  WHERE le.valuenum IS NOT NULL
),
itc AS (
  -- 4. keep only the first lab and categorize
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    ref_range_upper,
    CASE
      WHEN valuenum <= ref_range_upper THEN 'NORMAL'
      WHEN valuenum > ref_range_upper
           AND valuenum <= 2 * ref_range_upper THEN 'BORDERLINE'
      ELSE 'ELEVATED'
    END AS troponin_category
  FROM initial_troponin
  WHERE rn = 1
),
quantiles AS (
  -- 5. aggregate by category, compute counts, mean, and full quantiles array
  SELECT
    troponin_category,
    COUNT(*) AS patient_count,
    AVG(valuenum) AS mean_val,
    APPROX_QUANTILES(valuenum, 100) AS qs
  FROM itc
  GROUP BY troponin_category
),
final AS (
  -- 6. extract median and IQR from the quantiles array, compute percentages
  SELECT
    troponin_category,
    patient_count,
    ROUND(100.0 * patient_count / SUM(patient_count) OVER (), 2) AS pct_of_cohort,
    ROUND(mean_val, 4) AS mean_troponin,
    qs[OFFSET(50)] AS median_troponin,
    qs[OFFSET(75)] - qs[OFFSET(25)] AS iqr_troponin
  FROM quantiles
)
SELECT *
FROM final
ORDER BY troponin_category;