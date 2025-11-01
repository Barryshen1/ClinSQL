WITH ami_admissions AS (
  -- Get admissions with AMI diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    -- ICD-10 AMI: I21.x, I22.x; ICD-9 AMI: 410.x
    (
      (d.icd_version = 10 AND (LEFT(d.icd_code, 3) = 'I21' OR LEFT(d.icd_code, 3) = 'I22'))
      OR
      (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '410')
    )
),
male_49_59 AS (
  -- Get male patients aged 49-59
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 49 AND 59
),
troponin_t_items AS (
  -- Get itemids for Troponin T
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin AS (
  -- For each qualifying admission, get the first Troponin T value
  SELECT
    a.subject_id,
    a.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom
  FROM ami_admissions a
  INNER JOIN male_49_59 p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  INNER JOIN troponin_t_items tti ON l.itemid = tti.itemid
  WHERE l.valuenum IS NOT NULL
    AND LOWER(l.valueuom) = 'ng/ml'
),
first_troponin_per_admission AS (
  -- Get only the first Troponin T per admission
  SELECT
    subject_id,
    hadm_id,
    valuenum AS first_troponin_t
  FROM (
    SELECT
      subject_id,
      hadm_id,
      valuenum,
      charttime,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM first_troponin
  )
  WHERE rn = 1
    AND valuenum > 0.04
)
SELECT
  COUNT(*) AS n_admissions,
  APPROX_QUANTILES(first_troponin_t, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(first_troponin_t, 4)[OFFSET(1)] AS iqr_25,
  APPROX_QUANTILES(first_troponin_t, 4)[OFFSET(3)] AS iqr_75
FROM first_troponin_per_admission
;