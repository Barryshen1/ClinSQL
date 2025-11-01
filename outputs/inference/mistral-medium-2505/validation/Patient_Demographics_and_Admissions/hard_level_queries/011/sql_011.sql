WITH hemorrhagic_stroke_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-9 codes for hemorrhagic stroke
    (icd_version = 9 AND icd_code IN ('431', '4329'))
    OR
    -- ICD-10 codes for hemorrhagic stroke
    (icd_version = 10 AND icd_code LIKE 'I61%' OR icd_code = 'I629')
)

SELECT COUNT(DISTINCT a.hadm_id) AS qualifying_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
JOIN hemorrhagic_stroke_codes hsc
  ON d.icd_code = hsc.icd_code AND d.icd_version = hsc.icd_version
WHERE
  -- Female patients
  p.gender = 'F'
  -- Age 68-78 at admission (anchor_age is age at anchor_year)
  AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 68 AND 78
  -- Medicare insurance
  AND a.insurance = 'Medicare'
  -- Admitted from emergency department
  AND a.admission_location = 'EMERGENCY DEPARTMENT'
  -- Principal diagnosis (seq_num = 1)
  AND d.seq_num = 1
  -- Documented discharge (discharge_location not null)
  AND a.discharge_location IS NOT NULL;