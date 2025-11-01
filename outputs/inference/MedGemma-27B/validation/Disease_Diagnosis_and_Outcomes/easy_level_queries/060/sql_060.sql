WITH relevant_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    p.gender,
    p.anchor_age,
    d.long_title AS diagnosis_description
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND d.icd_code LIKE '57%' -- ICD-10 codes for upper GI bleed start with 57
    AND a.admission_type = 'EMERGENCY' -- Assuming primary upper GI bleed is usually an emergency admission
)
SELECT
  PERCENTILE_CONT(0.25, icu.los) AS percentile_25_los
FROM
  relevant_admissions AS ra
INNER JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` AS icu ON ra.hadm_id = icu.hadm_id
WHERE
  icu.los > 0;