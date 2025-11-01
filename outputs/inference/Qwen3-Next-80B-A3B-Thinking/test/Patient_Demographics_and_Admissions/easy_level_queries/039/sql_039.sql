WITH pneumonia_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND di.long_title LIKE '%pneumonia%'
),
first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  WHERE i.subject_id IN (SELECT subject_id FROM pneumonia_patients)
)
SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS percentile_25
FROM first_icu_stay
WHERE rn = 1;