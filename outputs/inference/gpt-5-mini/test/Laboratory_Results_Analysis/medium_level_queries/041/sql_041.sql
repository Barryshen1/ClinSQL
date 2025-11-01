WITH hs_items AS (
  -- Identify candidate high-sensitivity Troponin T lab itemids by label keywords
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND (LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high%')
),

first_hs_lab AS (
  -- earliest hs-TnT lab per hospital admission (hadm_id)
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC, l.labevent_id ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN hs_items h ON l.itemid = h.itemid
  WHERE l.valuenum IS NOT NULL
),

initial_hs AS (
  -- keep only the first hs-TnT per admission and convert to ng/mL
  SELECT
    fh.subject_id,
    fh.hadm_id,
    fh.charttime,
    fh.valuenum,
    fh.valueuom,
    CASE
      WHEN fh.valueuom IS NULL THEN NULL
      WHEN LOWER(fh.valueuom) LIKE '%ng/ml%' THEN fh.valuenum
      WHEN LOWER(fh.valueuom) LIKE '%ng/l%' THEN fh.valuenum / 1000.0
      WHEN LOWER(fh.valueuom) LIKE '%pg/ml%' THEN fh.valuenum / 1000.0
      -- unknown or uncommon units => NULL
      ELSE NULL
    END AS initial_value_ng_ml
  FROM first_hs_lab fh
  WHERE fh.rn = 1
),

acs_admissions AS (
  -- identify admissions with an ICD diagnosis consistent with ACS (text-based heuristic)
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
      LOWER(COALESCE(dd.long_title, '')) LIKE '%myocardial infarction%'
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%acute coronary%'
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%unstable angina%'
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%stemi%'
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%nstemi%'
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%acute myocardial%'
    )
),

cohort AS (
  -- join everything, restrict to male patients 43-53, ACS admissions, and initial value > ULN (0.014 ng/mL)
  SELECT
    ih.subject_id,
    ih.hadm_id,
    ih.charttime,
    ih.initial_value_ng_ml
  FROM initial_hs ih
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ih.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN acs_admissions acs
    ON ih.hadm_id = acs.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND ih.initial_value_ng_ml IS NOT NULL
    -- ULN assumed 14 ng/L == 0.014 ng/mL
    AND ih.initial_value_ng_ml > 0.014
)

-- final aggregation: median and IQR using APPROX_QUANTILES (100 -> percentiles)
SELECT
  q[OFFSET(50)] AS median_ng_per_mL,
  q[OFFSET(25)] AS p25_ng_per_mL,
  q[OFFSET(75)] AS p75_ng_per_mL,
  SAFE_CAST(q[OFFSET(75)] - q[OFFSET(25)] AS FLOAT64) AS iqr_ng_per_mL,
  (SELECT COUNT(*) FROM cohort) AS sample_size
FROM (
  SELECT APPROX_QUANTILES(initial_value_ng_ml, 100) AS q
  FROM cohort
);