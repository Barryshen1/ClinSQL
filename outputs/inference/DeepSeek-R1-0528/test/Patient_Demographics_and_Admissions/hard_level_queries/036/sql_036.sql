SELECT COUNT(*) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  ON adm.hadm_id = dx.hadm_id AND dx.seq_num = 1  -- Principal diagnosis
WHERE
  pat.gender = 'F'  -- Female
  AND adm.admission_location = 'EMERGENCY ROOM'  -- ED admission
  AND adm.insurance = 'Medicare'  -- Medicare insurance
  AND (  -- Acute pancreatitis (ICD-9: 577.0, ICD-10: K85.x)
    (dx.icd_version = 9 AND dx.icd_code = '5770') 
    OR 
    (dx.icd_version = 10 AND dx.icd_code LIKE 'K85%')
  )
  AND (  -- Age 72-82 at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) 
    BETWEEN 72 AND 82
  );