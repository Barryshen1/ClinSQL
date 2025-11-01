WITH AKI_Patients AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_code LIKE 'N17%' -- AKI ICD-10 codes
), ICU_Stays AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.subject_id IN (SELECT subject_id FROM AKI_Patients)
)
SELECT
  PERCENTILE_CONT(0.25, los) AS percentile_25_icu_los
FROM ICU_Stays;