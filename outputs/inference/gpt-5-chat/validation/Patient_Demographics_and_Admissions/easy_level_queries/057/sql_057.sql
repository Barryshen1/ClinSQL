WITH stroke_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND (
           icd_code LIKE '433%' OR 
           icd_code LIKE '434%' OR 
           icd_code LIKE '436%'
        ))
     OR (icd_version = 10 AND (
           icd_code LIKE 'I61%' OR
           icd_code LIKE 'I63%' OR
           icd_code LIKE 'I64%'
        ))
),
stroke_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN stroke_codes sc
    ON di.icd_code = sc.icd_code AND di.icd_version = sc.icd_version
),
first_admissions AS (
  SELECT subject_id, hadm_id, admittime
  FROM (
    SELECT a.subject_id, a.hadm_id, a.admittime,
           ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  )
  WHERE rn = 1
),
first_icu_in_first_adm AS (
  SELECT subject_id, hadm_id, los
  FROM (
    SELECT icu.subject_id, icu.hadm_id, icu.los,
           ROW_NUMBER() OVER (PARTITION BY icu.subject_id, icu.hadm_id ORDER BY icu.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  )
  WHERE rn = 1
),
cohort AS (
  SELECT p.subject_id, p.anchor_age, p.gender, icu.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN first_admissions fa
    ON p.subject_id = fa.subject_id
  INNER JOIN stroke_admissions sa
    ON fa.subject_id = sa.subject_id AND fa.hadm_id = sa.hadm_id
  INNER JOIN first_icu_in_first_adm icu
    ON fa.subject_id = icu.subject_id AND fa.hadm_id = icu.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
),
percentiles AS (
  SELECT
    PERCENTILE_CONT(los, 0.25) AS percentile_25,
    PERCENTILE_CONT(los, 0.75) AS percentile_75
  FROM cohort
)
SELECT
  percentile_75 - percentile_25 AS iqr_los_days,
  percentile_25,
  percentile_75
FROM percentiles;