WITH index_admissions AS (
  -- identify the index (first) admission per patient
  SELECT
    a.* EXCEPT (admittime),
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE
    a.hadm_id IS NOT NULL
),

principal_dx AS (
  -- principal diagnosis (seq_num = 1) with human-readable description
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
      ON d.icd_code = di.icd_code
      AND d.icd_version = di.icd_version
  WHERE
    d.seq_num = 1
),

hip_fracture_principal AS (
  -- flag principal diagnoses that look like hip fractures by text patterns
  SELECT
    pd.subject_id,
    pd.hadm_id,
    pd.icd_code,
    pd.long_title
  FROM
    principal_dx pd
  WHERE
    -- lower-case matching for common hip fracture phrases
    (
      (LOWER(COALESCE(pd.long_title, '')) LIKE '%hip%' AND LOWER(COALESCE(pd.long_title, '')) LIKE '%fracture%')
      OR LOWER(COALESCE(pd.long_title, '')) LIKE '%fracture of femur%'
      OR LOWER(COALESCE(pd.long_title, '')) LIKE '%femoral neck%'
      OR LOWER(COALESCE(pd.long_title, '')) LIKE '%neck of femur%'
      OR LOWER(COALESCE(pd.long_title, '')) LIKE '%pertrochanteric%'
      OR LOWER(COALESCE(pd.long_title, '')) LIKE '%subtrochanteric%'
    )
)

SELECT
  COUNT(DISTINCT ia.hadm_id) AS index_admission_count
FROM
  index_admissions ia
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ia.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ia.hadm_id = a.hadm_id
  JOIN hip_fracture_principal hf
    ON ia.hadm_id = hf.hadm_id
WHERE
  ia.rn = 1  -- keep only index (first) admission per patient
  AND p.gender = 'F'
  AND p.anchor_age BETWEEN 46 AND 56
  AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
  -- transferred from another hospital: either admission_type flagged or admission_location text indicates hospital transfer
  AND (
    LOWER(COALESCE(a.admission_type, '')) = 'transfer'
    OR (LOWER(COALESCE(a.admission_location, '')) LIKE '%transfer%' AND LOWER(COALESCE(a.admission_location, '')) LIKE '%hospital%')
  );