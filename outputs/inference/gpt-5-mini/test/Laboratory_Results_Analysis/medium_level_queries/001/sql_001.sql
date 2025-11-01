WITH troponin_items AS (
  -- Identify lab itemids that look like Troponin T
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%troponin-t%'
     OR LOWER(label) LIKE '%troponin t hs%'
     OR LOWER(label) LIKE '%tnt%'
),
ami_admissions AS (
  -- Admissions for female patients age 40-50 with an AMI diagnosis
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON di.icd_code = dicd.icd_code
       AND di.icd_version = dicd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%myocardial infarction%'
    )
),
first_troponin_per_adm AS (
  -- For each AMI admission, get the earliest Troponin T lab (numeric) during the admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    le.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC, le.storetime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  JOIN ami_admissions aa
    ON le.hadm_id = aa.hadm_id
  WHERE le.valuenum IS NOT NULL
    -- restrict to measurements taken during the hospital admission
    AND le.charttime >= aa.admittime
    AND le.charttime <= aa.dischtime
)
SELECT
  category,
  COUNT(*) AS count_admissions
FROM (
  SELECT
    CASE
      -- Prefer lab-specific reference range when available
      WHEN ref_range_upper IS NOT NULL AND valuenum <= ref_range_upper THEN 'normal'
      WHEN ref_range_upper IS NOT NULL AND valuenum > ref_range_upper AND valuenum <= 2 * ref_range_upper THEN 'borderline'
      WHEN ref_range_upper IS NOT NULL AND valuenum > 2 * ref_range_upper THEN 'elevated'
      -- Fallback thresholds when ref_range_upper is missing (assumes ng/mL)
      WHEN ref_range_upper IS NULL AND valuenum <= 0.01 THEN 'normal'
      WHEN ref_range_upper IS NULL AND valuenum > 0.01 AND valuenum <= 0.1 THEN 'borderline'
      WHEN ref_range_upper IS NULL AND valuenum > 0.1 THEN 'elevated'
      ELSE 'unknown'
    END AS category
  FROM first_troponin_per_adm
  WHERE rn = 1
)
GROUP BY category
ORDER BY category;