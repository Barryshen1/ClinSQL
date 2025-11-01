WITH cohort AS (
  -- Patients meeting demographic and diagnosis criteria
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON di.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (
      -- ICD-9 chest pain: 7865*
      (di.icd_version = 9 AND (
         di.icd_code LIKE '7865%'
         OR di.icd_code LIKE '410%'
       ))
      -- ICD-10 chest pain: R07%
      OR (di.icd_version = 10 AND (
         di.icd_code LIKE 'R07%'
         OR di.icd_code LIKE 'I21%'
         OR di.icd_code LIKE 'I22%'
       ))
    )
),
troponin_labs AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
),
first_trop AS (
  -- First Troponin T per admission
  SELECT
    t.subject_id,
    t.hadm_id,
    t.charttime,
    t.valuenum,
    ROW_NUMBER() OVER (PARTITION BY t.hadm_id ORDER BY t.charttime ASC) AS rn
  FROM troponin_labs t
  JOIN cohort c
    ON t.subject_id = c.subject_id
   AND t.hadm_id = c.hadm_id
),
filtered_first AS (
  SELECT subject_id, hadm_id, valuenum
  FROM first_trop
  WHERE rn = 1
    AND valuenum > 0.01
)
SELECT
  AVG(valuenum) AS mean_trop_t,
  STDDEV(valuenum) AS sd_trop_t,
  MIN(valuenum) AS min_trop_t,
  MAX(valuenum) AS max_trop_t
FROM filtered_first;