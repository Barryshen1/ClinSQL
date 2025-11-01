SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY le.valuenum) AS p75_glucose
FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
  ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON di.hadm_id = adm.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON adm.hadm_id = le.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
  ON le.itemid = dli.itemid
WHERE (dicd.long_title LIKE '%ischemic stroke%' OR dicd.long_title LIKE '%cerebral infarction%')
  AND pat.gender = 'F'
  AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) = 82
  AND le.charttime BETWEEN adm.admittime AND adm.dischtime
  AND LOWER(dli.label) LIKE '%glucose%'
  AND le.valuenum IS NOT NULL;