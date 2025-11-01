WITH ami_admissions AS (
  -- Identify admissions for female patients aged 55-65 with AMI
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND (
      -- ICD-10 AMI: I21.x, I22.x; ICD-9 AMI: 410.x
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
      OR
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
    )
),
hs_tnt_items AS (
  -- Find itemids for hs-TnT in d_labitems
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND LOWER(label) LIKE '%high%'
),
first_hs_tnt AS (
  -- For each qualifying admission, get the first hs-TnT value
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN hs_tnt_items i ON l.itemid = i.itemid
    JOIN ami_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE
    l.valuenum IS NOT NULL
    AND LOWER(l.valueuom) LIKE '%ng/ml%'
),
cohort AS (
  -- Only keep admissions where first hs-TnT > 0.01 ng/mL
  SELECT
    f.subject_id,
    f.hadm_id,
    f.valuenum AS hs_tnt_first,
    f.charttime
  FROM first_hs_tnt f
  WHERE f.rn = 1
    AND f.valuenum > 0.01
)
SELECT
  COUNT(DISTINCT c.subject_id) AS patient_count,
  COUNT(DISTINCT c.hadm_id) AS admission_count,
  ROUND(AVG(c.hs_tnt_first), 4) AS hs_tnt_mean,
  ROUND(APPROX_QUANTILES(c.hs_tnt_first, 2)[OFFSET(1)], 4) AS hs_tnt_median,
  ROUND(APPROX_QUANTILES(c.hs_tnt_first, 4)[OFFSET(1)], 4) AS hs_tnt_iqr_25,
  ROUND(APPROX_QUANTILES(c.hs_tnt_first, 4)[OFFSET(3)], 4) AS hs_tnt_iqr_75
FROM cohort c
;