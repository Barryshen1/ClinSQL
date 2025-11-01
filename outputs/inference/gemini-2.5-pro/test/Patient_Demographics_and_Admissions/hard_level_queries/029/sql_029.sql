WITH HipFractureAdmissions AS (
  -- This CTE identifies all hospital admissions where the principal diagnosis is a hip fracture.
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- A sequence number of 1 indicates a principal diagnosis.
    seq_num = 1
    -- Filter for ICD codes corresponding to hip fractures.
    AND (
      -- ICD-9 codes for fracture of neck of femur.
      (icd_version = 9 AND icd_code LIKE '820%')
      -- ICD-10 codes for fractures of the proximal femur (hip).
      -- Note: Dots are removed from ICD-10 codes in this table (e.g., S72.0 -> S720).
      OR (icd_version = 10 AND (
          icd_code LIKE 'S720%' -- Fracture of neck of femur
          OR icd_code LIKE 'S721%' -- Pertrochanteric fracture
          OR icd_code LIKE 'S722%' -- Subtrochanteric fracture
        )
      )
    )
)
SELECT
  COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
JOIN
  HipFractureAdmissions AS hf
  ON adm.hadm_id = hf.hadm_id
WHERE
  -- 1. Female patients
  pat.gender = 'F'
  -- 2. Aged 46-56 (inclusive)
  AND pat.anchor_age BETWEEN 46 AND 56
  -- 3. Insurance is Medicare
  AND adm.insurance = 'Medicare'
  -- 4. Transferred from another hospital
  AND adm.admission_location = 'TRANSFER FROM HOSPITAL';