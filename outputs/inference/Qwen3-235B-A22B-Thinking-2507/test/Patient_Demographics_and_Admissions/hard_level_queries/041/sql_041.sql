SELECT COUNT(*) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  ON a.hadm_id = d.hadm_id AND d.seq_num = 1
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
  ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND a.admission_location IN ('EMERGENCY ROOM', 'EMERGENCY ROOM ADMIT')
  AND LOWER(dd.long_title) LIKE '%osteomyelitis%'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 80 AND 90;