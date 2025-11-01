WITH female_medicare_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),

ed_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.admission_location,
    a.insurance
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_medicare_patients fmp ON a.subject_id = fmp.subject_id
  WHERE
    a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
),

principal_diagnosis_cholecystitis AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN
    ed_admissions ea ON d.subject_id = ea.subject_id AND d.hadm_id = ea.hadm_id
  WHERE
    d.seq_num = 1  -- Principal diagnosis
    AND (
      (d.icd_version = 10 AND d.icd_code = 'K81.0')  -- ICD-10 code for acute cholecystitis
      OR
      (d.icd_version = 9 AND d.icd_code = '575.0')   -- ICD-9 code for acute cholecystitis
    )
)

SELECT
  COUNT(DISTINCT hadm_id) AS total_index_admissions
FROM
  principal_diagnosis_cholecystitis;