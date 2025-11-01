WITH stroke_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.anchor_age, p.gender
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND LOWER(dicd.long_title) LIKE '%stroke%'
),
first_icu_stays AS (
  SELECT 
    sp.subject_id,
    sp.hadm_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, SECOND) / 86400.0 AS los_days
  FROM stroke_patients sp
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON sp.subject_id = i.subject_id AND sp.hadm_id = i.hadm_id
  WHERE i.outtime IS NOT NULL
    AND i.intime IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY sp.hadm_id ORDER BY i.intime) = 1
)
SELECT 
  PERCENTILE_CONT(los_days, 0.75) - PERCENTILE_CONT(los_days, 0.25) AS iqr_los_days
FROM first_icu_stays;