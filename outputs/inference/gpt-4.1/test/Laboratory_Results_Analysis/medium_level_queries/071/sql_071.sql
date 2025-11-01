WITH acs_icd_codes AS (
  -- List of ICD codes for ACS (ICD-9 and ICD-10)
  SELECT '410' AS icd_code, 9 AS icd_version UNION ALL -- Acute MI
  SELECT '411', 9 UNION ALL -- Unstable angina/other acute ischemic heart disease
  SELECT 'I20', 10 UNION ALL -- Unstable angina
  SELECT 'I21', 10 UNION ALL -- Acute MI
  SELECT 'I22', 10 UNION ALL -- Subsequent MI
  SELECT 'I24', 10          -- Other acute ischemic heart diseases
),
acs_admissions AS (
  -- Admissions with ACS diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN acs_icd_codes acs
    ON d.icd_code = acs.icd_code AND d.icd_version = acs.icd_version
),
female_43_53 AS (
  -- Female patients aged 43-53
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 43 AND 53
),
cohort AS (
  -- Admissions for female patients aged 43-53 with ACS
  SELECT a.subject_id, a.hadm_id, admittime, dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN acs_admissions acs ON a.subject_id = acs.subject_id AND a.hadm_id = acs.hadm_id
  JOIN female_43_53 f ON a.subject_id = f.subject_id
),
troponin_t_items AS (
  -- Itemids for Troponin T
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin_t AS (
  -- First Troponin T per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    l.ref_range_lower,
    l.ref_range_upper
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN troponin_t_items tti ON l.itemid = tti.itemid
  JOIN cohort c ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE l.valuenum IS NOT NULL
    AND l.charttime >= c.admittime AND l.charttime <= c.dischtime
),
initial_troponin_t AS (
  -- Earliest Troponin T per admission
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum,
    valueuom,
    ref_range_lower,
    ref_range_upper
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM first_troponin_t
  )
  WHERE rn = 1
),
troponin_category AS (
  -- Categorize Troponin T
  SELECT
    it.subject_id,
    it.hadm_id,
    it.valuenum,
    it.valueuom,
    it.ref_range_lower,
    it.ref_range_upper,
    CASE
      WHEN it.ref_range_upper IS NOT NULL AND it.ref_range_lower IS NOT NULL THEN
        CASE
          WHEN it.valuenum <= it.ref_range_upper AND it.valuenum >= it.ref_range_lower THEN 'Normal'
          WHEN it.valuenum > it.ref_range_upper AND it.valuenum <= it.ref_range_upper * 1.2 THEN 'Borderline'
          WHEN it.valuenum > it.ref_range_upper * 1.2 THEN 'Elevated'
          ELSE 'Unknown'
        END
      ELSE
        -- Fallback: use 0.03 ng/mL as upper limit if ref_range_upper missing
        CASE
          WHEN it.valuenum <= 0.03 THEN 'Normal'
          WHEN it.valuenum > 0.03 AND it.valuenum <= 0.036 THEN 'Borderline'
          WHEN it.valuenum > 0.036 THEN 'Elevated'
          ELSE 'Unknown'
        END
    END AS troponin_t_category
  FROM initial_troponin_t it
),
final_cohort AS (
  -- Cohort with LOS and Troponin T category
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    SAFE_DIVIDE(TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND), 86400) AS los_days,
    t.troponin_t_category
  FROM cohort c
  JOIN troponin_category t ON c.subject_id = t.subject_id AND c.hadm_id = t.hadm_id
  WHERE t.troponin_t_category IN ('Normal', 'Borderline', 'Elevated')
)
SELECT
  troponin_t_category,
  COUNT(*) AS n_patients,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percent_patients,
  ROUND(AVG(los_days), 2) AS avg_los_days
FROM final_cohort
GROUP BY troponin_t_category
ORDER BY
  CASE troponin_t_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;