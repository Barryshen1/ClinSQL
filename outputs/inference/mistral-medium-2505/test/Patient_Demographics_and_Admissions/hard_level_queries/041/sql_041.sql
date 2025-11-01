WITH female_medicare_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.admission_location,
    a.insurance,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY DEPARTMENT'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 80 AND 90
),

osteomyelitis_diagnoses AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    d.icd_code,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    d.icd_code LIKE 'M86.%' -- Osteomyelitis ICD-10 codes
),

index_admissions AS (
  SELECT
    fmp.subject_id,
    fmp.hadm_id,
    fmp.admittime,
    fmp.age_at_admission,
    od.icd_code,
    od.long_title
  FROM
    female_medicare_patients fmp
  JOIN
    osteomyelitis_diagnoses od
  ON
    fmp.subject_id = od.subject_id
    AND fmp.hadm_id = od.hadm_id
  WHERE
    -- Ensure this is the first admission for the patient (index admission)
    NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE
        a2.subject_id = fmp.subject_id
        AND a2.admittime < fmp.admittime
    )
    -- Ensure this is the principal diagnosis (lowest seq_num)
    AND od.seq_num = (
      SELECT MIN(seq_num)
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE subject_id = od.subject_id AND hadm_id = od.hadm_id
    )
)

SELECT
  COUNT(DISTINCT hadm_id) AS number_of_index_admissions
FROM
  index_admissions;