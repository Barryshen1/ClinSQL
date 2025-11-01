SELECT STDDEV(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS sd_length_of_stay
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id AND p.subject_id = d.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
  ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 51 AND 61
  AND d.seq_num = 1
  AND did.long_title LIKE '%hemorrhagic%'
  AND a.dischtime IS NOT NULL;