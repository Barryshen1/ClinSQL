SELECT AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS avg_hospital_los
FROM physionet-data.mimiciv_3_1_hosp.admissions a
JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 86 AND 96
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd 
      ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
    WHERE d.hadm_id = a.hadm_id
      AND (
        LOWER(d_icd.long_title) LIKE '%gastrointestinal%bleed%'
        OR LOWER(d_icd.long_title) LIKE '%upper%gastrointestinal%hemorrhage%'
        OR LOWER(d_icd.long_title) LIKE '%gastrointestinal%hemorrhage%'
        OR LOWER(d_icd.long_title) LIKE '%hemorrhage%gastric%'
        OR LOWER(d_icd.long_title) LIKE '%hemorrhage%esophageal%'
        OR LOWER(d_icd.long_title) LIKE '%hemorrhage%duodenal%'
        OR LOWER(d_icd.long_title) LIKE '%peptic%ulcer%hemorrhage%'
        OR d.icd_code LIKE 'K25%'
        OR d.icd_code LIKE 'K26%'
        OR d.icd_code LIKE 'K27%'
        OR d.icd_code LIKE 'K28%'
        OR d.icd_code LIKE 'K92%'
      )
  )
  AND EXISTS (
    SELECT 1
    FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd 
      ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
    WHERE d.hadm_id = a.hadm_id
      AND (
        LOWER(d_icd.long_title) LIKE '%copd%exacerbation%'
        OR LOWER(d_icd.long_title) LIKE '%chronic obstructive pulmonary disease%exacerbation%'
        OR d.icd_code = 'J44.1'
      )
  );