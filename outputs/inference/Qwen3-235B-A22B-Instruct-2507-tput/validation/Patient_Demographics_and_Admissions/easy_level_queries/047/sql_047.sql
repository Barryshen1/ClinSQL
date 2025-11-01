WITH aki_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    -- Compute age at admission
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 82 AND 92
    -- AKI: ICD-10 N17 or ICD-9 584
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '584%')
    )
),
first_icu_stays AS (
  SELECT 
    i.subject_id,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN aki_patients ap
    ON i.subject_id = ap.subject_id
)
SELECT 
  PERCENTILE_CONT(los, 0.25) OVER() AS icu_los_25th_percentile
FROM first_icu_stays
WHERE rn = 1
LIMIT 1;