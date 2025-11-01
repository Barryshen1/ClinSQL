SELECT
  MIN(le.valuenum) AS min_troponin
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  ON a.hadm_id = di.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
  ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
JOIN
  physionet-data.mimiciv_3_1_hosp.labevents le
  ON a.hadm_id = le.hadm_id
JOIN
  physionet-data.mimiciv_3_1_hosp.d_labitems dl
  ON le.itemid = dl.itemid
WHERE
  p.gender = 'M'
  AND p.anchor_age = 57
  AND LOWER(d.long_title) LIKE '%acute coronary syndrome%'
  AND LOWER(dl.label) LIKE '%troponin%'
  AND le.valuenum IS NOT NULL
  AND le.charttime BETWEEN a.admittime AND a.dischtime;