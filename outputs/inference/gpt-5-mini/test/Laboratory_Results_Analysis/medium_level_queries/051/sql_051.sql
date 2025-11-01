WITH patients_80_90_male AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 80 AND 90
),

acs_admissions AS (
  -- admissions with at least one diagnosis suggestive of ACS
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
    AND d.icd_version = dicd.icd_version
  WHERE a.subject_id IN (SELECT subject_id FROM patients_80_90_male)
    -- look for common ACS-related keywords in the ICD long title (case-insensitive)
    AND (
      LOWER(COALESCE(dicd.long_title, '')) LIKE '%myocardial%'
      OR LOWER(COALESCE(dicd.long_title, '')) LIKE '%infarct%'
      OR LOWER(COALESCE(dicd.long_title, '')) LIKE '%unstable angina%'
      OR LOWER(COALESCE(dicd.long_title, '')) LIKE '%acute coronary%'
    )
),

hs_tnt_labs AS (
  -- select lab events corresponding to (high-sensitivity) Troponin T
  SELECT
    le.labevent_id,
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    di.label
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  JOIN acs_admissions a
    ON le.hadm_id = a.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND (
      -- common label patterns for Troponin T / high-sensitivity Troponin T
      LOWER(di.label) LIKE '%troponin t%'
      OR LOWER(di.label) LIKE '%hs troponin t%'
      OR LOWER(di.label) LIKE '%tnt%'
      OR LOWER(di.label) LIKE '%troponin-t%'
      OR LOWER(di.label) LIKE '%troponin t, hs%'
      OR LOWER(di.label) LIKE '%high sensitivity troponin t%'
    )
    -- ensure the lab occurred during the admission window
    AND le.charttime BETWEEN a.admittime AND a.dischtime
),

first_hs_tnt_per_admission AS (
  -- pick the first hs-TnT per hadm_id (earliest charttime)
  SELECT
    h.*,
    a.admittime,
    a.dischtime,
    -- hospital LOS in fractional days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE), 60.0 * 24.0) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY h.hadm_id ORDER BY h.charttime ASC, h.labevent_id ASC) AS rn
  FROM hs_tnt_labs h
  JOIN acs_admissions a
    ON h.hadm_id = a.hadm_id
)
SELECT
  category,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_cohort,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM (
  SELECT
    hadm_id,
    subject_id,
    valuenum,
    los_days,
    CASE
      WHEN valuenum <= 14 THEN 'Normal'
      WHEN valuenum > 14 AND valuenum <= 52 THEN 'Borderline'
      WHEN valuenum > 52 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS category
  FROM first_hs_tnt_per_admission
  WHERE rn = 1
)
GROUP BY category
ORDER BY
  -- order categories in a clinically meaningful order
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
    ELSE 4
  END;