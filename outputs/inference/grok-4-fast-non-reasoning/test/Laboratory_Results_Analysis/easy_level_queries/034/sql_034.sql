SELECT MIN(le.valuenum) AS min_serum_sodium
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON a.hadm_id = di.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age = 65
  AND di.icd_version = '10'  -- Focus on ICD-10 for heart failure (I50*)
  AND di.icd_code LIKE 'I50%'
  AND le.itemid IN (225603, 227464)  -- Serum Sodium (from d_labitems)
  AND le.valuenum IS NOT NULL
  AND le.charttime BETWEEN a.admittime AND a.dischtime;