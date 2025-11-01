WITH sepsis_patients AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE UPPER(d.long_title) LIKE '%SEPSIS%'
     OR UPPER(d.long_title) LIKE '%SEPTICEMIA%'
)
SELECT
  STDDEV_SAMP(ic.los) AS icu_los_stddev_days
FROM sepsis_patients sp
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON sp.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
  ON sp.subject_id = ic.subject_id
  AND sp.hadm_id = ic.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 90 AND 100;