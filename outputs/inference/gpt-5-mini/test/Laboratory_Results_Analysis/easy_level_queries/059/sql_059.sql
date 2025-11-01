WITH sepsis_adm AS (
  -- Admissions with a diagnosis whose description mentions sepsis/septicemia
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
     OR LOWER(dd.long_title) LIKE '%septicemia%'
),

platelet_items AS (
  -- Lab itemids that correspond to platelet tests
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%platelet%'
),

platelet_on_discharge_per_adm AS (
  -- For each sepsis admission of a male patient, pick the last platelet lab on the discharge date
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    l.valuenum AS platelet_val,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime DESC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN sepsis_adm s
    ON a.hadm_id = s.hadm_id
   AND a.subject_id = s.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
  JOIN platelet_items pi
    ON l.itemid = pi.itemid
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
    -- On the same calendar day as discharge
    AND DATE(l.charttime) = DATE(a.dischtime)
    -- numeric platelet values only, exclude non-positive/uninterpretable entries
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
)

SELECT
  -- approximate 75th percentile of platelet values (same units as recorded in labevents)
  (APPROX_QUANTILES(platelet_val, 100))[OFFSET(75)] AS platelet_75th_percentile,
  COUNT(*) AS n_admissions_included
FROM (
  -- take only one platelet value per admission (the last on discharge day)
  SELECT subject_id, hadm_id, platelet_val
  FROM platelet_on_discharge_per_adm
  WHERE rn = 1
);