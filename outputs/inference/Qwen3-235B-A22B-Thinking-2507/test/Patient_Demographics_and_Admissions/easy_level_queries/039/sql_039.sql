WITH pneumonia_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
),
qualifying_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 43 AND 53
),
combined_admissions AS (
  SELECT 
    qa.hadm_id,
    qa.subject_id
  FROM qualifying_admissions qa
  INNER JOIN pneumonia_admissions pa
    ON qa.hadm_id = pa.hadm_id
),
first_icu_stays AS (
  SELECT 
    i.hadm_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN combined_admissions ca
    ON i.hadm_id = ca.hadm_id
)
SELECT 
  PERCENTILE_CONT(los, 0.25) OVER () AS p25_los
FROM first_icu_stays
WHERE rn = 1
LIMIT 1;