WITH female_aki_patients AS (
  -- Get female patients aged 48-58 with AKI
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      -- ICD-9 codes for AKI (e.g., 584.*)
      (d.icd_version = 9 AND d.icd_code LIKE '584.%')
      OR
      -- ICD-10 codes for AKI (e.g., N17.*)
      (d.icd_version = 10 AND d.icd_code LIKE 'N17.%')
    )
)

SELECT
  PERCENTILE_CONT(i.los, 0.25) OVER() AS percentile_25_icu_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` i
JOIN female_aki_patients f
  ON i.subject_id = f.subject_id
LIMIT 1;  -- Only need the percentile value;