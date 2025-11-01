WITH age_calc AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.insurance,
    a.admission_location,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
)
SELECT
  COUNT(DISTINCT ac.hadm_id) AS num_index_admissions
FROM age_calc ac
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON ac.subject_id = d.subject_id
  AND ac.hadm_id = d.hadm_id
  AND d.seq_num = 1
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON d.icd_code = dd.icd_code
  AND d.icd_version = dd.icd_version
WHERE ac.gender = 'F'
  AND ac.age_at_admit BETWEEN 46 AND 56
  AND ac.insurance = 'Medicare'
  AND UPPER(ac.admission_location) LIKE '%TRANSFER FROM HOSPITAL%'
  AND (
    -- ICD-9 hip fracture range
    (d.icd_version = 9 AND d.icd_code LIKE '820%')
    -- ICD-10 hip fracture range (S72.0-, S72.1-, S72.2-)
    OR (d.icd_version = 10 AND (
          d.icd_code LIKE 'S720%' OR
          d.icd_code LIKE 'S721%' OR
          d.icd_code LIKE 'S722%'
       ))
  );