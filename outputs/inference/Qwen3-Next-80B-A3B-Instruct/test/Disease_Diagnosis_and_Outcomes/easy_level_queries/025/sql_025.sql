SELECT STDDEV_SAMP(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS sd_los_days
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
  ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87
  AND d.seq_num = 1
  AND LOWER(d_icd.long_title) LIKE '%upper gi%'
  AND (LOWER(d_icd.long_title) LIKE '%hemorrhage%'
       OR LOWER(d_icd.long_title) LIKE '%bleed%'
       OR LOWER(d_icd.long_title) LIKE '%hemorrhagic%'
       OR LOWER(d_icd.long_title) LIKE '%gastrointestinal%');