WITH ich_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Composite risk score components
    CASE WHEN di_icd.icd_code LIKE 'I60%' OR di_icd.icd_code LIKE 'I61%' OR di_icd.icd_code LIKE 'I62%' THEN 1 ELSE 0 END AS has_ich,
    CASE WHEN di_comorb.icd_code IN ('I10','I11','I12','I13','I15') THEN 1 ELSE 0 END AS has_hypertension,
    CASE WHEN di_comorb2.icd_code LIKE 'E10%' OR di_comorb2.icd_code LIKE 'E11%' OR di_comorb2.icd_code LIKE 'E12%' OR di_comorb2.icd_code LIKE 'E13%' OR di_comorb2.icd_code LIKE 'E14%' THEN 1 ELSE 0 END AS has_diabetes,
    CASE WHEN p.drug LIKE '%warfarin%' OR p.drug LIKE '%apixaban%' OR p.drug LIKE '%rivaroxaban%' OR p.drug LIKE '%dabigatran%' OR p.drug LIKE '%edoxaban%' THEN 1 ELSE 0 END AS on_anticoag,
    CASE WHEN le_inr.valuenum > 1.5 THEN 1 ELSE 0 END AS inr_elevated,
    CASE WHEN le_platelet.valuenum < 150 THEN 1 ELSE 0 END AS platelets_low
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di_icd ON a.hadm_id = di_icd.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di_icd_desc ON di_icd.icd_code = di_icd_desc.icd_code AND di_icd.icd_version = di_icd_desc.icd_version
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di_comorb ON a.hadm_id = di_comorb.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di_comorb_desc ON di_comorb.icd_code = di_comorb_desc.icd_code AND di_comorb.icd_version = di_comorb_desc.icd_version
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di_comorb2 ON a.hadm_id = di_comorb2.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di_comorb2_desc ON di_comorb2.icd_code = di_comorb2_desc.icd_code AND di_comorb2.icd_version = di_comorb2_desc.icd_version
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.prescriptions p ON a.hadm_id = p.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.labevents le_inr ON a.hadm_id = le_inr.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl_inr ON le_inr.itemid = dl_inr.itemid AND dl_inr.label = 'INR'
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.labevents le_platelet ON a.hadm_id = le_platelet.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl_platelet ON le_platelet.itemid = dl_platelet.itemid AND dl_platelet.label = 'Platelets'
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (di_icd_desc.long_title LIKE '%intracranial hemorrhage%' OR di_icd.icd_code IN ('I60','I61','I62'))
    AND le_inr.charttime >= a.admittime AND le_inr.charttime <= a.dischtime
    AND le_platelet.charttime >= a.admittime AND le_platelet.charttime <= a.dischtime
),
risk_score AS (
  SELECT *,
    has_hypertension + has_diabetes + on_anticoag + inr_elevated + platelets_low AS composite_risk_score
  FROM ich_patients
  WHERE has_ich = 1
),
quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY composite_risk_score) AS risk_quartile
  FROM risk_score
)
SELECT
  risk_quartile,
  COUNT(*);