WITH stroke_admissions AS (
  -- admissions for female patients aged 82 with an ischemic stroke diagnosis
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    USING (subject_id, hadm_id)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddesc
    ON diag.icd_code = ddesc.icd_code
   AND diag.icd_version = ddesc.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age = 82
    AND (
      -- ICD-10 cerebral infarction (ischemic stroke)
      (diag.icd_version = 10 AND SAFE_CAST(diag.icd_code AS STRING) LIKE 'I63%')
      -- Common ICD-9 ischemic stroke codes (433*, 434*)
      OR (diag.icd_version = 9 AND (SAFE_CAST(diag.icd_code AS STRING) LIKE '433%' OR SAFE_CAST(diag.icd_code AS STRING) LIKE '434%'))
      -- fallback: textual match in diagnosis description
      OR (ddesc.long_title IS NOT NULL AND (
            LOWER(ddesc.long_title) LIKE '%ischemic%'
         OR LOWER(ddesc.long_title) LIKE '%cerebral infarct%'
      ))
    )
),

glucose_labs AS (
  -- glucose labs within 24 hours of admission; normalize to mg/dL
  SELECT
    sa.subject_id,
    sa.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    CASE
      WHEN le.valuenum IS NULL THEN NULL
      WHEN LOWER(COALESCE(le.valueuom, '')) LIKE '%mmol%' THEN le.valuenum * 18
      ELSE le.valuenum
    END AS glucose_mg_dl
  FROM stroke_admissions sa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    USING (subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    USING (itemid)
  WHERE LOWER(dlab.label) LIKE '%glucose%'
    AND le.charttime BETWEEN sa.admittime AND sa.admittime + INTERVAL 24 HOUR
    AND le.valuenum IS NOT NULL
    AND SAFE_CAST(le.valuenum AS FLOAT64) > 0
),

first_glucose AS (
  -- pick the earliest glucose per admission
  SELECT
    subject_id,
    hadm_id,
    glucose_mg_dl,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
  FROM glucose_labs
)

-- 75th percentile (approximate) of the admission glucose values (mg/dL)
SELECT
  (SELECT APPROX_QUANTILES(glucose_mg_dl, 100)[OFFSET(75)]
   FROM first_glucose
   WHERE rn = 1) AS p75_glucose_mg_dl,
  (SELECT COUNT(*) FROM first_glucose WHERE rn = 1) AS n_admissions_included,
  'mg/dL' AS units
;