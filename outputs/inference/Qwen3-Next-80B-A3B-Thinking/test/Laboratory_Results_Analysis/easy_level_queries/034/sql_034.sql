SELECT MIN(lab.valuenum) AS min_sodium
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
  ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
  ON adm.hadm_id = lab.hadm_id
WHERE pat.gender = 'M'
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) = 65
  AND LOWER(d_diag.long_title) LIKE '%heart failure%'
  AND lab.itemid = 50983
  AND lab.charttime BETWEEN adm.admittime AND adm.dischtime;