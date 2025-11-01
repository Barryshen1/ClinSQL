WITH osteomy_icd AS (
  -- ICD codes (any version) whose description mentions "osteomyelitis"
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%osteomyelitis%'
),

principal_osteomy AS (
  -- Admissions where the principal (seq_num = 1) diagnosis is osteomyelitis
  SELECT d.subject_id, d.hadm_id, d.icd_code, d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN osteomy_icd o
    ON d.icd_code = o.icd_code
   AND d.icd_version = o.icd_version
  WHERE d.seq_num = 1
)

SELECT
  COUNT(DISTINCT a.hadm_id) AS num_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN principal_osteomy po
  ON a.hadm_id = po.hadm_id
 AND a.subject_id = po.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 85 AND 95
  AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
  -- Heuristic for "transferred from another hospital":
  AND (
        LOWER(COALESCE(a.admission_location, '')) LIKE '%transfer%'
     OR LOWER(COALESCE(a.admission_type, '')) = 'transfer'
      );