WITH acs_admissions AS (
  -- admissions with any diagnosis matching ACS-related text in the diagnosis description
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute%'
    AND (
      LOWER(dd.long_title) LIKE '%myocard%'    -- myocardial / myocardium variations
      OR LOWER(dd.long_title) LIKE '%infarct%' -- infarction
      OR LOWER(dd.long_title) LIKE '%coronar%' -- coronary
      OR LOWER(dd.long_title) LIKE '%ischemi%' -- ischemia
      OR LOWER(dd.long_title) LIKE '%angina%'  -- unstable angina
    )
),

cohort_admissions AS (
  -- admissions for male patients aged 90-100 (anchor_age used for age)
  SELECT a.*
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN acs_admissions ac
    USING(hadm_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),

tnt_lab_items AS (
  -- lab items that correspond to Troponin T (label-based matching to capture variants)
  SELECT itemid, label, loinc_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%' 
     OR LOWER(label) LIKE '%troponin-t%'
     OR LOWER(label) LIKE '%troponin t hs%'
     OR LOWER(label) LIKE '%troponin-t, high sensitivity%'
),

tnt_labevents AS (
  -- troponin lab events (valuenum not null) joined to their d_labitems match
  SELECT le.*
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN tnt_lab_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
),

first_troponin_per_admission AS (
  -- left join so admissions with no troponin are preserved; pick earliest troponin per hadm_id when present
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    le.labevent_id,
    le.charttime,
    le.valuenum,
    le.value,
    le.ref_range_lower,
    le.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY le.charttime ASC, le.storetime ASC, le.labevent_id ASC) AS rn
  FROM cohort_admissions a
  LEFT JOIN tnt_labevents le
    ON le.hadm_id = a.hadm_id
   AND le.charttime BETWEEN a.admittime AND a.dischtime
)

SELECT
  tnt_category,
  COUNT(*) AS n_admissions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_cohort,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0), 2) AS mean_los_days
FROM (
  -- only keep the index (earliest) troponin row per admission (rn = 1).
  -- Admissions with no troponin will have NULL labevent_id and rn = 1 (from the LEFT JOIN).
  SELECT
    hadm_id,
    admittime,
    dischtime,
    valuenum,
    ref_range_upper,
    CASE
      WHEN labevent_id IS NULL THEN 'no_troponin'
      -- Use reference range when available
      WHEN ref_range_upper IS NOT NULL AND valuenum <= ref_range_upper THEN 'normal'
      WHEN ref_range_upper IS NOT NULL AND valuenum > ref_range_upper AND valuenum <= 2 * ref_range_upper THEN 'borderline'
      WHEN ref_range_upper IS NOT NULL AND valuenum > 2 * ref_range_upper THEN 'elevated'
      -- Fallback numeric thresholds when no reference range present (common hs-TnT thresholds)
      WHEN ref_range_upper IS NULL AND valuenum <= 0.014 THEN 'normal'
      WHEN ref_range_upper IS NULL AND valuenum > 0.014 AND valuenum <= 0.04 THEN 'borderline'
      WHEN ref_range_upper IS NULL AND valuenum > 0.04 THEN 'elevated'
      ELSE 'unknown'
    END AS tnt_category
  FROM first_troponin_per_admission
  WHERE rn = 1
) categorized
GROUP BY tnt_category
ORDER BY
  CASE tnt_category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
    WHEN 'no_troponin' THEN 4
    ELSE 5
  END;