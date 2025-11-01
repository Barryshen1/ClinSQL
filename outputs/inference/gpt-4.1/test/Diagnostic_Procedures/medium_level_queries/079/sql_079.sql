WITH
-- Step 1: Identify women age 71-81
female_71_81 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 71 AND 81
),

-- Step 2: Identify LGIB admissions and diagnosis type
lgib_codes AS (
  -- List of ICD codes for LGIB (ICD-9 and ICD-10)
  SELECT '5693' AS icd_code UNION ALL -- ICD-9: Hemorrhage of rectum and anus
  SELECT '56986' UNION ALL            -- ICD-9: Dieulafoy lesion (LGIB)
  SELECT '5781' UNION ALL             -- ICD-9: Blood in stool
  SELECT '5789' UNION ALL             -- ICD-9: Hemorrhage of gastrointestinal tract, unspecified
  SELECT 'K921' UNION ALL             -- ICD-10: Melena
  SELECT 'K625' UNION ALL             -- ICD-10: Hemorrhage of anus and rectum
  SELECT 'K626' UNION ALL             -- ICD-10: Ulcer of anus and rectum
  SELECT 'K550' UNION ALL             -- ICD-10: Acute vascular disorders of intestine
  SELECT 'K551' UNION ALL             -- ICD-10: Chronic vascular disorders of intestine
  SELECT 'K552' UNION ALL             -- ICD-10: Vascular disorders of intestine, unspecified
  SELECT 'K553' UNION ALL             -- ICD-10: Angiodysplasia of colon
  SELECT 'K558' UNION ALL             -- ICD-10: Other specified vascular disorders of intestine
  SELECT 'K559' UNION ALL             -- ICD-10: Vascular disorder of intestine, unspecified
  SELECT 'K928'                       -- ICD-10: Other specified diseases of digestive system
),

lgib_admissions AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE WHEN d.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN lgib_codes c
    ON REPLACE(UPPER(d.icd_code), '.', '') = c.icd_code
  WHERE d.subject_id IN (SELECT subject_id FROM female_71_81)
),

-- Step 3: Get LOS and LOS group
admission_los AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.subject_id IN (SELECT subject_id FROM female_71_81)
),

-- Step 4: Identify radiography/CT procedures per admission
ct_rad_proc_codes AS (
  -- List of ICD-9 procedure codes for CT/radiography
  SELECT '8703' AS icd_code UNION ALL -- CT scan of abdomen
  SELECT '8704' UNION ALL             -- CT scan of pelvis
  SELECT '8838' UNION ALL             -- CT scan of abdomen and pelvis
  SELECT '8801' UNION ALL             -- X-ray of abdomen
  SELECT '8802' UNION ALL             -- X-ray of pelvis
  SELECT '8803' UNION ALL             -- X-ray of lower GI
  SELECT '8839'                       -- CT scan, other
),

ct_rad_procs AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(*) AS n_ct_rad
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN ct_rad_proc_codes c
    ON REPLACE(UPPER(p.icd_code), '.', '') = c.icd_code
  GROUP BY p.subject_id, p.hadm_id
),

-- Step 5: Combine all info per admission
admission_summary AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.diagnosis_type,
    a.los_group,
    IFNULL(c.n_ct_rad, 0) AS n_ct_rad
  FROM lgib_admissions l
  JOIN admission_los a
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  LEFT JOIN ct_rad_procs c
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE a.los_group IS NOT NULL
)

-- Step 6: Aggregate mean CT/radiography per admission by diagnosis type and LOS group
SELECT
  diagnosis_type,
  los_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(n_ct_rad), 2) AS mean_ct_rad_per_admission
FROM admission_summary
GROUP BY diagnosis_type, los_group
ORDER BY diagnosis_type, los_group;