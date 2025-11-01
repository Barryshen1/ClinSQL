WITH troponin_lab_items AS (
  -- pick lab items whose label indicates Troponin T / high-sensitivity Troponin T
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE (
    LOWER(label) LIKE '%troponin t%' OR
    LOWER(label) LIKE '%troponin-t%' OR
    LOWER(label) LIKE '%hs troponin%' OR
    LOWER(label) LIKE '%high-sensitivity troponin%' OR
    LOWER(label) LIKE '%high sensitivity troponin%'
  )
),

admissions_with_ischemia AS (
  -- admissions that have at least one diagnosis mentioning ischemia / ischemic
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%ischemi%'
),

initial_troponin_per_admission AS (
  -- for each admission, find the earliest troponin T lab (within that hadm_id)
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    COALESCE(SAFE_CAST(le.ref_range_upper AS FLOAT64), 14.0) AS ref_range_upper_fallback,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime, le.storetime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_lab_items tli
    ON le.itemid = tli.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON le.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
  WHERE le.hadm_id IS NOT NULL
    AND le.valuenum IS NOT NULL
    -- restrict to the target demographic here to avoid extra rows
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 36 AND 46
    -- only admissions with ischemic heart disease
    AND EXISTS (
      SELECT 1 FROM admissions_with_ischemia awi WHERE awi.hadm_id = le.hadm_id
    )
),

initial_troponin_over_uln AS (
  -- keep only the initial troponin per admission and those > ULN (using fallback if needed)
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum,
    ref_range_upper_fallback
  FROM initial_troponin_per_admission
  WHERE rn = 1
    AND valuenum > ref_range_upper_fallback
)

SELECT
  stats.q[OFFSET(1)] AS p25,
  stats.q[OFFSET(2)] AS p50,
  stats.q[OFFSET(3)] AS p75,
  stats.q[OFFSET(0)] AS min_value,
  stats.q[OFFSET(4)] AS max_value,
  stats.cnt AS n_observations
FROM (
  SELECT
    APPROX_QUANTILES(valuenum, 4) AS q,
    COUNT(*) AS cnt
  FROM initial_troponin_over_uln
) AS stats;