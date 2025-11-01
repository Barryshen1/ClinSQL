WITH ak_patients AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_code LIKE 'N17%' 
    AND d.icd_version = 10  -- ICD-10 codes for AKI
),
icu_stays_with_aki AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    (EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age)) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN ak_patients a 
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND i.intime IS NOT NULL
    AND i.outtime IS NOT NULL
    AND (EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age)) BETWEEN 82 AND 92
),
first_icu_per_patient AS (
  SELECT 
    subject_id,
    DATEDIFF(outtime, intime) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM icu_stays_with_aki
)
SELECT 
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25_los
FROM first_icu_per_patient
WHERE rn = 1;