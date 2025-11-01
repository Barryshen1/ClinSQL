WITH base_patients AS (
  SELECT 
    subject_id, 
    anchor_age, 
    gender, 
    dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' 
    AND anchor_age BETWEEN 71 AND 81
),
base_admissions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime, 
    deathtime, 
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  INNER JOIN base_patients USING (subject_id)
),
dvt_adms AS (
  SELECT DISTINCT 
    subject_id, 
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN base_admissions ba USING (subject_id, hadm_id)
  WHERE ((icd_version = 9 AND icd_code LIKE '453%')
     OR (icd_version = 10 AND icd_code LIKE 'I82%'))
),
pe_adms AS (
  SELECT DISTINCT 
    subject_id, 
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN base_admissions ba USING (subject_id, hadm_id)
  WHERE ((icd_version = 9 AND icd_code LIKE '415.1%')
     OR (icd_version = 10 AND icd_code LIKE 'I26%'))
),
high_comorb_adms AS (
  SELECT 
    subject_id, 
    hadm_id, 
    ANY_VALUE(drg_severity) AS drg_severity,
    ANY_VALUE(drg_mortality) AS drg_mortality
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  WHERE drg_severity >= 3 
    AND drg_mortality IS NOT NULL
  GROUP BY subject_id, hadm_id
),
cohort_dvt AS (
  SELECT 
    ba.*,
    bp.anchor_age,
    bp.dod,
    hca.drg_mortality AS risk_score,
    CASE WHEN pa.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS major_comp
  FROM base_admissions ba
  INNER JOIN base_patients bp USING (subject_id)
  INNER JOIN dvt_adms da USING (subject_id, hadm_id)
  INNER JOIN high_comorb_adms hca USING (subject_id, hadm_id)
  LEFT JOIN pe_adms pa USING (subject_id, hadm_id)
  WHERE ba.los > 0  -- Exclude invalid LOS
),
general_cohort AS (
  SELECT 
    ba.*,
    bp.anchor_age,
    bp.dod,
    dc.drg_mortality AS risk_score,
    CASE WHEN pa.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS major_comp
  FROM base_admissions ba
  INNER JOIN base_patients bp USING (subject_id)
  LEFT JOIN (
    SELECT 
      subject_id, 
      hadm_id, 
      ANY_VALUE(drg_mortality) AS drg_mortality
    FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
    GROUP BY subject_id, hadm_id
  ) dc USING (subject_id, hadm_id)
  LEFT JOIN pe_adms pa USING (subject_id, hadm_id)
  WHERE dc.drg_mortality IS NOT NULL
    AND ba.los > 0  -- Exclude invalid LOS
),
dvt_with_mort AS (
  SELECT 
    *,
    CASE 
      WHEN dod IS NULL THEN 0
      WHEN DATE(dod) < DATE(admittime) THEN 0
      WHEN DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 90 THEN 1
      ELSE 0
    END AS day90_mort
  FROM cohort_dvt
),
general_with_mort AS (
  SELECT 
    *,
    CASE 
      WHEN dod IS NULL THEN 0
      WHEN DATE(dod) < DATE(admittime) THEN 0
      WHEN DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 90 THEN 1
      ELSE 0
    END AS day90_mort
  FROM general_cohort
),
-- Main stats
main_stats AS (
  SELECT 
    'DVT High Comorbidity' AS group_type,
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] AS median_risk_score,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(25)] AS iqr_25,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(75)] AS iqr_75,
    AVG(CAST(day90_mort AS FLOAT64)) AS day90_mortality_rate,
    AVG(CAST(major_comp AS FLOAT64)) AS major_complication_rate,
    APPROX_QUANTILES(IF(hospital_expire_flag = 0, los, NULL), 100)[OFFSET(50)] AS median_survivor_los
  FROM dvt_with_mort
  
  UNION ALL
  
  SELECT 
    'General Inpatients' AS group_type,
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] AS median_risk_score,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(25)] AS iqr_25,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(75)] AS iqr_75,
    AVG(CAST(day90_mort AS FLOAT64)) AS day90_mortality_rate,
    AVG(CAST(major_comp AS FLOAT64)) AS major_complication_rate,
    APPROX_QUANTILES(IF(hospital_expire_flag = 0, los, NULL), 100)[OFFSET(50)] AS median_survivor_los
  FROM general_with_mort
),
-- Patient-specific: Risk percentile (median risk_score at age 76, then % of cohort <= that value)
patient_percentile AS (
  SELECT 
    'Patient Risk Percentile' AS metric,
    COALESCE(
      (SELECT APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] FROM dvt_with_mort WHERE anchor_age = 76),
      (SELECT APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] FROM dvt_with_mort)
    ) AS assumed_risk_score,
    AVG(CASE WHEN risk_score <= COALESCE(
      (SELECT APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] FROM dvt_with_mort WHERE anchor_age = 76),
      (SELECT APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] FROM dvt_with_mort)
    ) THEN 1.0 ELSE 0 END) * 100 AS risk_percentile
  FROM dvt_with_mort
)
SELECT * FROM main_stats
UNION ALL
SELECT metric, NULL AS n_admissions, assumed_risk_score AS median_risk_score, NULL AS iqr_25, NULL AS iqr_75, 
       NULL AS day90_mortality_rate, NULL AS major_complication_rate, risk_percentile AS median_survivor_los
FROM patient_percentile;