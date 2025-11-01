SELECT MAX(l.valuenum) AS max_creatinine
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
  ON a.hadm_id = d.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
  ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
  ON a.hadm_id = l.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl 
  ON l.itemid = dl.itemid
WHERE 
  p.gender = 'M'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) = 66
  AND LOWER(dd.long_title) LIKE '%heart failure%'
  AND dl.label = 'Creatinine' 
  AND dl.fluid = 'Blood'
  AND l.charttime >= a.admittime 
  AND l.charttime <= a.admittime + INTERVAL '24' HOUR;