WITH hs_tnt_items AS (
  -- Find itemids for high-sensitivity Troponin T
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%' AND LOWER(label) LIKE '%sens%'
),

ihd_admissions AS (
  -- Identify admissions with ischemic heart disease (ICD-10: I20-I25, ICD-9: 410-414)
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE (
    (dx.icd_version = 9 AND SAFE_CAST(SUBSTR(dx.icd_code, 1, 3) AS INT64) BETWEEN 410 AND 414)
    OR
    (dx.icd_version = 10 AND SAFE_CAST(SUBSTR(dx.icd_code, 2, 2) AS INT64) BETWEEN 20 AND 25)
  )
),

cohort AS (
  -- Female, age 36-46, admitted with IHD
  SELECT adm.subject_id, adm.hadm_id
  FROM ihd_admissions adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 36 AND 46
),

initial_hs_tnt AS (
  -- For each admission, get the first hs-TnT lab value
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    l.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN hs_tnt_items i ON l.itemid = i.itemid
  JOIN cohort c ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE l.valuenum IS NOT NULL AND l.ref_range_upper IS NOT NULL
    -- Only keep values with numeric upper limit
    AND SAFE_CAST(l.ref_range_upper AS FLOAT64) IS NOT NULL
),

first_hs_tnt_per_admission AS (
  -- Get the earliest hs-TnT per admission
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    valueuom,
    SAFE_CAST(ref_range_upper AS FLOAT64) AS ref_range_upper
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM initial_hs_tnt
  )
  WHERE rn = 1
),

above_uln AS (
  -- Only keep those above upper limit of normal
  SELECT *
  FROM first_hs_tnt_per_admission
  WHERE valuenum > ref_range_upper
)

SELECT
  MIN(valuenum) AS min_hs_tnt,
  MAX(valuenum) AS max_hs_tnt,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS p25_hs_tnt,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS p50_hs_tnt,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS p75_hs_tnt,
  COUNT(*) AS n_patients
FROM above_uln
;