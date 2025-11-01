WITH
-- Get female patients aged 46-56 at admission
female_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 46 AND 56
),

-- Identify ACS admissions (using common ICD-10 codes for ACS)
acs_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (
      d.icd_code LIKE 'I21.%' OR  -- Acute myocardial infarction
      d.icd_code LIKE 'I20.%'     -- Angina pectoris
    )
),

-- Get first hs-TnT measurement per admission
first_hs_tnt AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
  ON
    l.itemid = dl.itemid
  WHERE
    l.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND dl.label LIKE '%Troponin T%'  -- Filter for hs-TnT tests
    AND l.valuenum IS NOT NULL
),

-- Categorize hs-TnT results
tnt_categories AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.valuenum,
    CASE
      WHEN f.valuenum < 14 THEN 'Normal'
      WHEN f.valuenum BETWEEN 14 AND 50 THEN 'Borderline'
      WHEN f.valuenum > 50 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS tnt_category
  FROM
    first_hs_tnt f
  WHERE
    f.rn = 1  -- Only first measurement per admission
),

-- Combine all data
final_data AS (
  SELECT
    a.hadm_id,
    a.los_days,
    tc.tnt_category
  FROM
    acs_admissions a
  LEFT JOIN
    tnt_categories tc
  ON
    a.hadm_id = tc.hadm_id
)

-- Final aggregation
SELECT
  tnt_category,
  COUNT(hadm_id) AS admission_count,
  ROUND(COUNT(hadm_id) * 100.0 / SUM(COUNT(hadm_id)) OVER(), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM
  final_data
GROUP BY
  tnt_category
ORDER BY
  CASE tnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
    ELSE 4
  END;