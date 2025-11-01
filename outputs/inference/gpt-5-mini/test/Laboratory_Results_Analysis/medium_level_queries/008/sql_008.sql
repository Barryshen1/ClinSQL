WITH troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

-- Admissions with any ACS-related diagnosis (ICD description text match)
acs_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
    AND d.icd_version = dicd.icd_version
  WHERE (
    LOWER(dicd.long_title) LIKE '%myocardial infarction%'
    OR LOWER(dicd.long_title) LIKE '%acute myocardial%'
    OR LOWER(dicd.long_title) LIKE '%unstable angina%'
    OR LOWER(dicd.long_title) LIKE '%nstemi%'
    OR LOWER(dicd.long_title) LIKE '%stemi%'
    OR LOWER(dicd.long_title) LIKE '%angina pectoris%'
    OR LOWER(dicd.long_title) LIKE '%angina%'
    OR LOWER(dicd.long_title) LIKE '%acute coronary%'
    OR LOWER(dicd.long_title) LIKE '%coronary%'
  )
),

-- Restrict to male patients aged 87-97 and keep only ACS admissions
acs_admissions_filtered AS (
  SELECT a.*
  FROM acs_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
),

-- For each subject, pick the index (first) ACS admission by admittime
index_acs AS (
  SELECT
    subject_id,
    FIRST_VALUE(hadm_id) OVER (PARTITION BY subject_id ORDER BY admittime ASC, hadm_id ASC) AS hadm_id,
    FIRST_VALUE(admittime) OVER (PARTITION BY subject_id ORDER BY admittime ASC, hadm_id ASC) AS admittime,
    FIRST_VALUE(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime ASC, hadm_id ASC) AS dischtime,
    FIRST_VALUE(hospital_expire_flag) OVER (PARTITION BY subject_id ORDER BY admittime ASC, hadm_id ASC) AS hospital_expire_flag
  FROM acs_admissions_filtered
  -- One row per (subject_id, hadm_id) is present above; we will distinct below
),

index_acs_distinct AS (
  SELECT DISTINCT subject_id, hadm_id, admittime, dischtime, hospital_expire_flag
  FROM index_acs
),

-- Get the first Troponin T measurement (index troponin) during the admission
first_troponin AS (
  SELECT
    ia.subject_id,
    ia.hadm_id,
    le.charttime,
    le.valuenum,
    le.value AS value_text,
    le.valueuom,
    le.ref_range_lower,
    le.ref_range_upper,
    le.flag,
    ROW_NUMBER() OVER (PARTITION BY ia.hadm_id ORDER BY le.charttime ASC, le.storetime ASC) AS rn
  FROM index_acs_distinct ia
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ia.hadm_id = le.hadm_id
    AND ia.subject_id = le.subject_id
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.charttime BETWEEN ia.admittime AND ia.dischtime
    -- ensure we have a numeric value for categorization; we'll further require ref_range_upper
    AND le.valuenum IS NOT NULL
),

index_troponin_filtered AS (
  -- keep only the first troponin per admission
  SELECT ft.subject_id, ft.hadm_id, ft.charttime, ft.valuenum, ft.ref_range_upper, ft.flag
  FROM first_troponin ft
  WHERE ft.rn = 1
),

-- Categorize troponin relative to the assay-specific upper reference limit
troponin_categorized AS (
  SELECT
    itf.*,
    CASE
      WHEN itf.valuenum IS NULL OR itf.ref_range_upper IS NULL THEN 'Unknown'
      WHEN itf.valuenum <= itf.ref_range_upper THEN 'Normal/Minimal'
      WHEN itf.valuenum > itf.ref_range_upper AND itf.valuenum <= 3 * itf.ref_range_upper THEN 'Borderline'
      WHEN itf.valuenum > 3 * itf.ref_range_upper THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM index_troponin_filtered itf
),

-- Join back with admission mortality flag and keep only the three required categories
final_cohort AS (
  SELECT
    tc.subject_id,
    tc.hadm_id,
    tc.troponin_category,
    ia.hospital_expire_flag
  FROM troponin_categorized tc
  JOIN index_acs_distinct ia
    ON tc.hadm_id = ia.hadm_id
  WHERE tc.troponin_category IN ('Normal/Minimal', 'Borderline', 'Elevated')
)

-- Aggregate: counts, percentages, and in-hospital mortality by category
SELECT
  troponin_category,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_cohort,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS mortality_rate_pct
FROM final_cohort
GROUP BY troponin_category
ORDER BY
  -- order categories from Normal -> Borderline -> Elevated
  CASE troponin_category
    WHEN 'Normal/Minimal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 99
  END;