SELECT MAX(le.valuenum) AS max_serum_creatinine
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.labevents le
  ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_labitems di
  ON le.itemid = di.itemid
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di_cd
  ON a.subject_id = di_cd.subject_id AND a.hadm_id = di_cd.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
  ON di_cd.icd_code = did.icd_code AND di_cd.icd_version = did.icd_version
WHERE p.gender = 'M'
  AND p.anchor_age = 66
  AND di.label IN ('Creatinine', 'CREATININE', 'Serum Creatinine', 'Creatinine, Serum')
  AND le.valuenum IS NOT NULL
  AND le.charttime >= a.admittime
  AND le.charttime <= a.admittime + INTERVAL 24 HOUR
  AND (
    (di_cd.icd_version = 9 AND di_cd.icd_code LIKE '428%')
    OR (di_cd.icd_version = 10 AND di_cd.icd_code LIKE 'I50%')
  );