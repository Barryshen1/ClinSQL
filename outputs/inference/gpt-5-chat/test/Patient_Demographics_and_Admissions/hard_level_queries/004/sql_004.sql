WITH principal_dx AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    di.icd_code,
    di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.seq_num = 1
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '730%')  -- ICD-9 osteomyelitis
      OR (di.icd_version = 10 AND di.icd_code LIKE 'M86%') -- ICD-10 osteomyelitis
    )
),
eligible_admissions AS (
  SELECT
    pat.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.admission_location,
    adm.insurance,
    pat.gender,
    pat.anchor_age,
    pat.anchor_year,
    -- compute age at admission:
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  JOIN principal_dx pdx
    ON adm.subject_id = pdx.subject_id
    AND adm.hadm_id = pdx.hadm_id
  WHERE pat.gender = 'F'
    AND LOWER(adm.insurance) = 'medicare'
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 85 AND 95
    AND UPPER(adm.admission_location) IN ('TRANSFER FROM HOSPITAL', 'TRANSFER FROM OTHER HOSPITAL')
)
-- pick index admission per subject_id
SELECT COUNT(*) AS num_index_admissions
FROM (
  SELECT subject_id, hadm_id
  FROM (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM eligible_admissions
  )
  WHERE rn = 1
);