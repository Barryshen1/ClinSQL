WITH PatientCohort AS (
  -- Select patients matching the criteria: female, age 44-54, intracranial hemorrhage
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.hadm_id IN (
      -- Find admissions with intracranial hemorrhage diagnosis
      SELECT
        hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        icd_code LIKE 'I60%' -- ICD-9 codes for intracranial hemorrhage
        OR icd_code LIKE 'I61%' -- ICD-9 codes for intracranial hemorrhage
        OR icd_code LIKE 'I62%' -- ICD-9 codes for intracranial hemorrhage
        OR icd_code LIKE 'I63%' -- ICD-9 codes for intracranial hemorrhage
        OR icd_code LIKE 'I64%' -- ICD-9 codes for intracranial hemorrhage
        OR icd_code LIKE 'I65%' -- ICD-9 codes for intracranial hemorrhage
        OR icd_code LIKE 'I66%' -- ICD-9 codes for intracranial hemorrhage
        OR icd_code LIKE 'I67%' -- ICD-9 codes for intracranial hemorrhage
        OR icd_code LIKE 'I68%' -- ICD-9 codes for intracranial hemorrhage
        OR icd_code LIKE 'I69%' -- ICD-9 codes for intracranial hemorrhage
        OR icd_code LIKE 'G43%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'G44%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'G45%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'G46%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'G47%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'G48%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'G49%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'I60%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'I61%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'I62%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'I63%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'I64%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE 'I65%' -- ICD-10 codes for intracranial hemorrhage (example)
        OR icd_code LIKE ';