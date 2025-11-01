SELECT icd_code
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd
  WHERE hadm_id = d.hadm_id
    AND (
      (icd_version = 9 AND icd_code LIKE '410.%' AND SUBSTR(d.icd_code, 6, 1) IN ('1','2'))
      OR (icd_version = 10 AND d.icd_code IN ('I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4'))
    )
);