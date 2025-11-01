SELECT PERCENTILE_CONT(i.los, 0.25) OVER() AS p25_icu_los_days
FROM physionet-data.mimiciv_3_1_icu.icustays i
JOIN (
  SELECT d.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE (
    LOWER(dicd.long_title) LIKE '%acute kidney injury%'
    OR LOWER(dicd.long_title) LIKE '%acute renal failure%'
    OR LOWER(dicd.long_title) LIKE '%acute renal insufficiency%'
    OR (dicd.icd_code IN ('584', '584.5', '584.6', '584.7', '584.9') AND dicd.icd_version = 9)
    OR (dicd.icd_code LIKE 'N17%' AND dicd.icd_version = 10)
  )
) akd ON i.subject_id = akd.subject_id AND i.hadm_id = akd.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.patients p
  ON i.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 48 AND 58
LIMIT 1;