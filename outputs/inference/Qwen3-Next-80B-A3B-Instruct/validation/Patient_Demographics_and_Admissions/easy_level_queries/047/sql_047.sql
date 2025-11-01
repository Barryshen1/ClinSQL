WITH aki_patients AS (
  SELECT DISTINCT d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON d.icd_code = ddi.icd_code AND d.icd_version = ddi.icd_version
  WHERE LOWER(ddi.long_title) LIKE '%acute kidney injury%'
     OR LOWER(ddi.long_title) LIKE '%acute renal failure%'
),
first_icu_stay AS (
  SELECT 
    i.subject_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
)
SELECT 
  APPROX_QUANTILES(fis.los, 100)[OFFSET(25)] AS p25_los_days
FROM first_icu_stay fis
JOIN aki_patients ap ON fis.subject_id = ap.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON fis.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 82 AND 92
  AND fis.rn = 1;