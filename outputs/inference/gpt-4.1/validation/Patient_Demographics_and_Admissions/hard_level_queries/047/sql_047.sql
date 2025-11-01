WITH
-- 1. Get principal hemorrhagic stroke ICD codes
hemorrhagic_stroke_icds AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10: I60, I61, I62
    (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^I60') OR
      REGEXP_CONTAINS(icd_code, r'^I61') OR
      REGEXP_CONTAINS(icd_code, r'^I62')
    ))
    -- ICD-9: 430, 431, 432
    OR (icd_version = 9 AND (
      icd_code IN ('430', '431', '432')
    ))
),

-- 2. Get index admissions (cohort)
index_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.admission_location,
    adm.insurance,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN hemorrhagic_stroke_icds icd
    ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE
    diag.seq_num = 1 -- principal diagnosis
    AND pat.gender = 'F'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND LOWER(adm.insurance) LIKE '%medicare%'
    AND (
      LOWER(adm.admission_location) LIKE '%emergency%' OR
      LOWER(adm.admission_location) LIKE '%ed%'
    )
    AND adm.dischtime IS NOT NULL
    AND adm.hospital_expire_flag = 0 -- exclude in-hospital deaths
),

-- 3. For each index admission, find 30-day readmission
readmissions AS (
  SELECT
    idx.subject_id,
    idx.hadm_id AS index_hadm_id,
    idx.admittime AS index_admittime,
    idx.dischtime AS index_dischtime,
    MIN(next.admittime) AS readmit_admittime,
    MIN(next.hadm_id) AS readmit_hadm_id
  FROM index_admissions idx
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
    ON idx.subject_id = next.subject_id
    AND next.admittime > idx.dischtime
    AND DATETIME_DIFF(next.admittime, idx.dischtime, DAY) <= 30
  GROUP BY idx.subject_id, idx.hadm_id, idx.admittime, idx.dischtime
),

-- 4. Combine index admissions with readmission status
index_with_readmit_flag AS (
  SELECT
    idx.*,
    CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS was_readmitted,
    DATETIME_DIFF(idx.dischtime, idx.admittime, DAY) AS los
  FROM index_admissions idx
  LEFT JOIN readmissions r
    ON idx.subject_id = r.subject_id AND idx.hadm_id = r.index_hadm_id
)

-- 5. Aggregate results
SELECT
  COUNT(*) AS n_index_admissions,
  SUM(was_readmitted) AS n_readmitted,
  ROUND(SUM(was_readmitted) / COUNT(*) * 100, 2) AS readmission_rate_percent,
  -- Median LOS for readmitted
  APPROX_QUANTILES(IF(was_readmitted = 1, los, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  -- Median LOS for non-readmitted
  APPROX_QUANTILES(IF(was_readmitted = 0, los, NULL), 2)[OFFSET(1)] AS median_los_nonreadmitted,
  -- % with LOS > 4 days (readmitted)
  ROUND(SUM(CASE WHEN was_readmitted = 1 AND los > 4 THEN 1 ELSE 0 END) / NULLIF(SUM(was_readmitted),0) * 100, 2) AS percent_los_gt4_readmitted,
  -- % with LOS > 4 days (non-readmitted)
  ROUND(SUM(CASE WHEN was_readmitted = 0 AND los > 4 THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN was_readmitted = 0 THEN 1 ELSE 0 END),0) * 100, 2) AS percent_los_gt4_nonreadmitted
FROM index_with_readmit_flag;