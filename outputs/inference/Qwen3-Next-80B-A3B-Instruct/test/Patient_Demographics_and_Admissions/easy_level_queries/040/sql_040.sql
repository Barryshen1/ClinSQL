SELECT APPROX_QUANTILES(i.los, 2)[OFFSET(1)] AS median_icu_los
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_icu.icustays i
  ON p.subject_id = i.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic
  ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 35 AND 45
  AND (
    (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438')
    OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I69')
    OR LOWER(dic.long_title) LIKE '%stroke%'
  );