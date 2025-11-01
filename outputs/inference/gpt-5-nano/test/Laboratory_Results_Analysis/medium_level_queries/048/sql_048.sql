WITH
-- 1) Female patients in target age range
eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
),

-- 2) Admissions with AMI diagnosis (ICD-9 410% OR ICD-10 I21*/I22*)
ami_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE (
          (di.icd_version = 9  AND di.icd_code LIKE '410%')
       OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
        )
),

-- 3) Filter to target females and ages (AMI admissions intersecting eligible patients)
target_admissions AS (
  SELECT DISTINCT aa.subject_id, aa.hadm_id
  FROM ami_admissions AS aa
  JOIN eligible_patients AS ep
    ON aa.subject_id = ep.subject_id
  -- ensure patient exists in patients table (redundant guard)
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON aa.subject_id = p.subject_id
),

-- 4) Troponin T measurements (hs-TnT) in hospital lab events
troponin_events AS (
  SELECT l.subject_id,
         l.hadm_id,
         l.charttime,
         l.valuenum,
         l.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE l.valuenum IS NOT NULL
    AND LOWER(d.label) LIKE '%troponin t%'
    AND LOWER(l.valueuom) LIKE '%ng/mL%'
),

-- 5) For each admission, identify the first hs-TnT value > 0.01 ng/mL
first_hstn AS (
  SELECT te.subject_id,
         te.hadm_id,
         MIN(te.charttime) AS first_time
  FROM troponin_events AS te
  JOIN target_admissions AS ta
    ON te.subject_id = ta.subject_id AND te.hadm_id = ta.hadm_id
  WHERE te.valuenum > 0.01
  GROUP BY te.subject_id, te.hadm_id
),

-- 6) First hs-TnT value per admission
first_vals AS (
  SELECT fh.subject_id,
         fh.hadm_id,
         te.valuenum
  FROM first_hstn AS fh
  JOIN troponin_events AS te
    ON te.subject_id = fh.subject_id
   AND te.hadm_id = fh.hadm_id
   AND te.charttime = fh.first_time
)

SELECT
  -- patient and admission counts
  (SELECT COUNT(DISTINCT subject_id) FROM target_admissions) AS patient_count,
  (SELECT COUNT(DISTINCT hadm_id) FROM first_vals) AS admission_count,
  -- HS-TnT mean
  (SELECT AVG(valuenum) FROM first_vals) AS mean_hstn,
  -- HS-TnT median
  (
    SELECT quant[OFFSET(2)]
    FROM (
      SELECT APPROX_QUANTILES(valuenum, 4) AS quant
      FROM first_vals
    )
  ) AS median_hstn,
  -- HS-TnT IQR (75th - 25th)
  (
    SELECT (quant[OFFSET(3)] - quant[OFFSET(1)])
    FROM (
      SELECT APPROX_QUANTILES(valuenum, 4) AS quant
      FROM first_vals
    )
  ) AS iqr_hstn
FROM (SELECT 1) AS dummy;