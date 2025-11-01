WITH patient_admissions AS (
  SELECT DISTINCT
    pat.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.deathtime,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON pat.subject_id = adm.subject_id
  WHERE pat.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 88 AND 98
),
pneumonia_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%pneumonia%'
),
icu_patients AS (
  SELECT DISTINCT pa.*
  FROM pneumonia_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON pa.hadm_id = icu.hadm_id
),
cohort_with_outcomes AS (
  SELECT
    icu.*,
    drg.drg_severity,
    -- AKI flag using ICD-10: N179, ICD-9: 5849
    (
      SELECT MAX(1)
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = icu.hadm_id
        AND (
          (di.icd_version = 10 AND d.icd_code = 'N179') OR
          (di.icd_version = 9 AND d.icd_code = '5849')
        )
    ) AS aki_flag,
    -- ARDS flag: ICD-10: J80, ICD-9: 51881
    (
      SELECT MAX(1)
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = icu.hadm_id
        AND (
          (di.icd_version = 10 AND d.icd_code = 'J80') OR
          (di.icd_version = 9 AND d.icd_code = '51881')
        )
    ) AS ards_flag
  FROM icu_patients icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.drgcodes drg
    ON icu.hadm_id = drg.hadm_id AND drg.drg_type = 'APR'
),
final_cohort AS (
  SELECT
    *,
    -- Survival days for decedents
    IF(hospital_expire_flag = 1, DATETIME_DIFF(deathtime, admittime, DAY), NULL) AS survival_days
  FROM cohort_with_outcomes
)
-- Final aggregation
SELECT
  COUNT(*) AS cohort_size,
  -- Distribution of drg_severity (proxy for composite risk score)
  MIN(drg_severity) AS risk_score_min,
  APPROX_QUANTILES(drg_severity, 100)[OFFSET(25)] AS risk_score_25th,
  APPROX_QUANTILES(drg_severity, 100)[OFFSET(50)] AS risk_score_median,
  APPROX_QUANTILES(drg_severity, 100)[OFFSET(75)] AS risk_score_75th,
  MAX(drg_severity) AS risk_score_max,
  -- In-hospital mortality rate
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  -- AKI rate
  AVG(CAST(aki_flag AS FLOAT64)) AS aki_rate,
  -- ARDS rate
  AVG(CAST(ards_flag AS FLOAT64)) AS ards_rate,
  -- Median survival days for decedents
  APPROX_QUANTILES(survival_days, 100 IGNORE NULLS)[OFFSET(50)] AS median_survival_days_decedents
FROM final_cohort;