WITH troponin_items AS (
  -- identify itemids that are troponin T tests by label
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

acs_hadm AS (
  -- admissions with an ACS-related diagnosis (by diagnosis description)
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE (
    LOWER(dd.long_title) LIKE '%myocardial infarction%'
    OR LOWER(dd.long_title) LIKE '%unstable angina%'
    OR LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
  )
),

cohort_admissions AS (
  -- male patients aged 79-89 with an ACS admission
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN acs_hadm acs
    ON a.hadm_id = acs.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
),

first_troponin_per_admission AS (
  -- for each admission in the cohort, pick the earliest troponin T lab (index draw)
  SELECT
    hadm_id,
    subject_id,
    charttime,
    valuenum,
    value,
    labevent_id
  FROM (
    SELECT
      le.subject_id,
      le.hadm_id,
      le.charttime,
      le.valuenum,
      le.value,
      le.labevent_id,
      ROW_NUMBER() OVER (
        PARTITION BY le.hadm_id
        ORDER BY le.charttime ASC, le.labevent_id ASC
      ) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_items ti
      ON le.itemid = ti.itemid
    JOIN cohort_admissions ca
      ON le.hadm_id = ca.hadm_id
    WHERE le.charttime >= ca.admittime
      AND le.charttime <= ca.dischtime
  )
  WHERE rn = 1
)

SELECT
  CASE
    WHEN ft.valuenum IS NOT NULL AND ft.valuenum <= 0.04 THEN 'normal (<=0.04)'
    WHEN ft.valuenum IS NOT NULL AND ft.valuenum > 0.04 AND ft.valuenum <= 0.1 THEN 'borderline (>0.04–0.1)'
    WHEN ft.valuenum IS NOT NULL AND ft.valuenum > 0.1 THEN 'elevated (>0.1)'
    ELSE 'unknown'
  END AS troponin_category,
  COUNT(*) AS admission_count
FROM first_troponin_per_admission ft
GROUP BY troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'normal (<=0.04)' THEN 1
    WHEN 'borderline (>0.04–0.1)' THEN 2
    WHEN 'elevated (>0.1)' THEN 3
    ELSE 4
  END;