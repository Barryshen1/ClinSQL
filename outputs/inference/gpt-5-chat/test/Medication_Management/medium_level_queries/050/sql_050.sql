WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
    MIN(icu.intime) AS icu_intime,
    MIN(icu.outtime) AS icu_outtime,
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 49 AND 59
  GROUP BY adm.subject_id, adm.hadm_id, pat.gender, pat.anchor_age, pat.anchor_year, adm.admittime
),
dx_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
           OR (d.icd_version = 9 AND d.icd_code LIKE '250._0')
           OR (d.icd_version = 9 AND d.icd_code LIKE '250._2')
             THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
           OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
             THEN 1 ELSE 0 END) AS has_hf
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
cohort_filtered AS (
  SELECT c.*
  FROM cohort c
  JOIN dx_flags dx
    ON c.subject_id = dx.subject_id AND c.hadm_id = dx.hadm_id
  WHERE dx.has_t2dm = 1 AND dx.has_hf = 1
),
presc_classes AS (
  SELECT 
    cf.subject_id,
    cf.hadm_id,
    cf.icu_intime,
    cf.icu_outtime,
    p.starttime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%insulin%' 
        OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%'
        OR LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%sitagliptin%'
        OR LOWER(p.drug) LIKE '%dapagliflozin%' THEN 'Antidiabetic'
      WHEN LOWER(p.drug) LIKE '%metoprolol%' OR LOWER(p.drug) LIKE '%atenolol%' OR LOWER(p.drug) LIKE '%carvedilol%'
        THEN 'Beta-Blocker'
      WHEN LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%enalapril%' OR LOWER(p.drug) LIKE '%captopril%'
        OR LOWER(p.drug) LIKE '%losartan%' OR LOWER(p.drug) LIKE '%valsartan%' OR LOWER(p.drug) LIKE '%sacubitril%'
        THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(p.drug) LIKE '%furosemide%' OR LOWER(p.drug) LIKE '%bumetanide%' OR LOWER(p.drug) LIKE '%torsemide%'
        THEN 'Loop Diuretic'
    END AS drug_class
  FROM cohort_filtered cf
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON cf.hadm_id = p.hadm_id
)
, presc_windows AS (
  SELECT 
    subject_id, hadm_id, drug_class,
    MAX(CASE WHEN starttime BETWEEN icu_intime AND DATETIME_ADD(icu_intime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS in_first_24h,
    MAX(CASE WHEN starttime BETWEEN DATETIME_SUB(icu_outtime, INTERVAL 48 HOUR) AND icu_outtime THEN 1 ELSE 0 END) AS in_final_48h
  FROM presc_classes
  WHERE drug_class IS NOT NULL
  GROUP BY subject_id, hadm_id, drug_class
),
status_counts AS (
  SELECT 
    drug_class,
    SUM(CASE WHEN in_first_24h = 1 AND in_final_48h = 1 THEN 1 ELSE 0 END) AS continued_cnt,
    SUM(CASE WHEN in_first_24h = 0 AND in_final_48h = 1 THEN 1 ELSE 0 END) AS initiated_cnt,
    SUM(CASE WHEN in_first_24h = 1 AND in_final_48h = 0 THEN 1 ELSE 0 END) AS discontinued_cnt,
    COUNT(DISTINCT hadm_id) AS total_patients
  FROM presc_windows
  GROUP BY drug_class
)
SELECT 
  drug_class,
  continued_cnt,
  initiated_cnt,
  discontinued_cnt,
  total_patients,
  ROUND(continued_cnt / total_patients * 100, 1) AS continued_pct,
  ROUND(initiated_cnt / total_patients * 100, 1) AS initiated_pct,
  ROUND(discontinued_cnt / total_patients * 100, 1) AS discontinued_pct
FROM status_counts
ORDER BY drug_class;