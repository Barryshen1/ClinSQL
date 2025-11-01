WITH female_medicare_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 36 AND 46
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'TRANSFER'
),

hemorrhagic_stroke_admissions AS (
  SELECT
    fmp.subject_id,
    fmp.hadm_id,
    fmp.admittime,
    di.seq_num,
    di.icd_code,
    di.icd_version,
    dicd.long_title
  FROM
    female_medicare_patients fmp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    fmp.subject_id = di.subject_id
    AND fmp.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
  ON
    di.icd_code = dicd.icd_code
    AND di.icd_version = dicd.icd_version
  WHERE
    di.seq_num = 1  -- Principal diagnosis
    AND di.icd_code LIKE 'I61%'  -- Hemorrhagic stroke ICD-10 codes
),

index_admissions AS (
  SELECT
    hsa.subject_id,
    hsa.hadm_id,
    hsa.admittime,
    ROW_NUMBER() OVER (PARTITION BY hsa.subject_id ORDER BY hsa.admittime) AS admission_rank
  FROM
    hemorrhagic_stroke_admissions hsa
  WHERE
    NOT EXISTS (
      SELECT 1
      FROM hemorrhagic_stroke_admissions prev
      WHERE
        prev.subject_id = hsa.subject_id
        AND prev.hadm_id < hsa.hadm_id  -- Ensure no prior admission with same diagnosis
    )
)

SELECT
  COUNT(DISTINCT subject_id) AS total_index_admissions
FROM
  index_admissions
WHERE
  admission_rank = 1;  -- First admission per patient;