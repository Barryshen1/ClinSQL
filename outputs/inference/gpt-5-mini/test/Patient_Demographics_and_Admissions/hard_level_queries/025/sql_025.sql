WITH first_admissions AS (
  -- identify the index (first) hospital admission per subject
  SELECT
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime, hadm_id) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

index_admissions AS (
  -- keep only the index admission for each subject
  SELECT
    fa.subject_id,
    fa.hadm_id,
    a.admittime,
    a.admission_location,
    a.insurance
  FROM first_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fa.hadm_id = a.hadm_id
  WHERE fa.rn = 1
),

principal_dx AS (
  -- principal diagnosis (seq_num = 1) for admissions
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    dd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE d.seq_num = 1
)

SELECT
  COUNT(DISTINCT ia.hadm_id) AS n_index_admissions
FROM index_admissions ia
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ia.subject_id = p.subject_id
JOIN principal_dx pd
  ON ia.hadm_id = pd.hadm_id
WHERE
  -- demographics
  p.gender = 'F'
  AND p.anchor_age BETWEEN 65 AND 75
  -- payer
  AND LOWER(ia.insurance) LIKE '%medicare%'
  -- admitted as a transfer (robust match)
  AND LOWER(ia.admission_location) LIKE '%transfer%'
  -- principal diagnosis text contains heart failure
  AND LOWER(COALESCE(pd.long_title, '')) LIKE '%heart failure%';