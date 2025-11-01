WITH patients_with_aki AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON p.subject_id = d.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND d.icd_code LIKE 'N17%'
    AND d.icd_version = 10
),
first_icu_stays AS (
  SELECT 
    subject_id,
    los,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS percentile_25
FROM first_icu_stays fis
JOIN patients_with_aki pwa 
  ON fis.subject_id = pwa.subject_id
WHERE fis.rn = 1;