WITH acs_admissions AS (
  -- female admissions age 46-56 with an ACS-related diagnosis (ICD description text search)
  SELECT DISTINCT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON di.icd_code = dicd.icd_code
   AND di.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 46 AND 56
    -- text match to capture acute MI / ACS / unstable angina / acute coronary descriptions
    AND (
      lower(dicd.long_title) LIKE '%acute%' 
      AND (
        lower(dicd.long_title) LIKE '%myocardial%' 
        OR lower(dicd.long_title) LIKE '%infarct%' 
        OR lower(dicd.long_title) LIKE '%unstable%' 
        OR lower(dicd.long_title) LIKE '%acute coronary%'
        OR lower(dicd.long_title) LIKE '%angina%'
      )
    )
),

troponin_events AS (
  -- first troponin measurement (numeric) during the admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    COALESCE(le.charttime, le.storetime) AS event_time,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY COALESCE(le.charttime, le.storetime) ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  JOIN acs_admissions aa
    ON le.hadm_id = aa.hadm_id
  WHERE lower(dl.label) LIKE '%troponin%'
    AND le.valuenum IS NOT NULL
),

first_hsTnT AS (
  -- keep only the first troponin per admission
  SELECT te.subject_id,
         te.hadm_id,
         te.valuenum
  FROM troponin_events te
  WHERE te.rn = 1
),

categorized AS (
  SELECT
    f.hadm_id,
    f.valuenum,
    CASE
      WHEN f.valuenum < 14 THEN 'Normal'
      WHEN f.valuenum >= 14 AND f.valuenum < 50 THEN 'Borderline'
      WHEN f.valuenum >= 50 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS category
  FROM first_hsTnT f
),

summary AS (
  SELECT
    c.category,
    COUNT(*) AS n,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_measured,
    ROUND(AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0), 2) AS mean_los_days
  FROM categorized c
  JOIN acs_admissions a
    ON c.hadm_id = a.hadm_id
  GROUP BY c.category
)

SELECT
  category,
  n,
  pct_of_measured,
  mean_los_days
FROM summary
ORDER BY CASE
         WHEN category = 'Normal' THEN 1
         WHEN category = 'Borderline' THEN 2
         WHEN category = 'Myocardial Injury' THEN 3
         ELSE 4 END;