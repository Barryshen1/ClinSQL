WITH stroke_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%stroke%' AND d.icd_version = 10
),
eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 35 AND 45
),
icu_stays AS (
  SELECT i.stay_id, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN stroke_patients sp ON i.hadm_id = sp.hadm_id
  INNER JOIN eligible_patients ep ON i.subject_id = ep.subject_id
)
SELECT APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los
FROM icu_stays;