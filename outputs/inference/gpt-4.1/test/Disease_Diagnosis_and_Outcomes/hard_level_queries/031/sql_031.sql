WITH asthma_admissions AS (
  -- Select female inpatients aged 85-95 with primary diagnosis of asthma exacerbation
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 85 AND 95
    AND diag.seq_num = 1
    AND (
      -- ICD-10 asthma: J45.x, J46
      (diag.icd_version = 10 AND (diag.icd_code LIKE 'J45%' OR diag.icd_code = 'J46'))
      -- ICD-9 asthma: 493.x
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '493%')
    )
),

comorbidity_scores AS (
  -- Calculate Charlson Comorbidity Index (CCI) for each admission
  -- Simplified mapping: sum weights for each comorbidity present
  SELECT
    aa.subject_id,
    aa.hadm_id,
    aa.anchor_age,
    aa.gender,
    aa.hospital_expire_flag,
    SUM(
      CASE
        -- Myocardial infarction
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%') OR (diag.icd_version = 9 AND diag.icd_code LIKE '410%') THEN 1
        -- Congestive heart failure
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%') OR (diag.icd_version = 9 AND diag.icd_code LIKE '428%') THEN 1
        -- Peripheral vascular disease
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'I73%') OR (diag.icd_version = 9 AND diag.icd_code LIKE '443%') THEN 1
        -- Cerebrovascular disease
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%') OR (diag.icd_version = 9 AND diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%') THEN 1
        -- Dementia
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'F03%') OR (diag.icd_version = 9 AND diag.icd_code LIKE '290%') THEN 1
        -- Chronic pulmonary disease (exclude asthma itself)
        WHEN (diag.icd_version = 10 AND (diag.icd_code LIKE 'J44%' OR diag.icd_code LIKE 'J43%')) OR (diag.icd_version = 9 AND diag.icd_code LIKE '496%') THEN 1
        -- Rheumatic disease
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'M05%') OR (diag.icd_version = 9 AND diag.icd_code LIKE '714%') THEN 1
        -- Diabetes (uncomplicated)
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'E10%' AND diag.icd_code NOT LIKE 'E10.2%') OR (diag.icd_version = 9 AND diag.icd_code LIKE '250%' AND diag.icd_code NOT LIKE '250.4%') THEN 1
        -- Diabetes (complicated)
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'E10.2%') OR (diag.icd_version = 9 AND diag.icd_code LIKE '250.4%') THEN 2
        -- Renal disease
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'N18%') OR (diag.icd_version = 9 AND diag.icd_code LIKE '585%') THEN 1
        -- Cancer
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'C%' AND diag.icd_code NOT LIKE 'C77%' AND diag.icd_code NOT LIKE 'C78%' AND diag.icd_code NOT LIKE 'C79%') OR (diag.icd_version = 9 AND diag.icd_code LIKE '140%' AND diag.icd_code NOT LIKE '196%' AND diag.icd_code NOT LIKE '197%' AND diag.icd_code NOT LIKE '198%') THEN 2
        -- Metastatic solid tumor
        WHEN (diag.icd_version = 10 AND (diag.icd_code LIKE 'C77%' OR diag.icd_code LIKE 'C78%' OR diag.icd_code LIKE 'C79%')) OR (diag.icd_version = 9 AND (diag.icd_code LIKE '196%' OR diag.icd_code LIKE '197%' OR diag.icd_code LIKE '198%')) THEN 6
        -- AIDS/HIV
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'B20%') OR (diag.icd_version = 9 AND diag.icd_code LIKE '042%') THEN 6
        ELSE 0
      END
    ) AS cci
  FROM
    asthma_admissions aa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON aa.hadm_id = diag.hadm_id
  GROUP BY
    aa.subject_id, aa.hadm_id, aa.anchor_age, aa.gender, aa.hospital_expire_flag
),

quartiles AS (
  -- Assign CCI quartiles
  SELECT
    *,
    NTILE(4) OVER (ORDER BY cci) AS cci_quartile
  FROM
    comorbidity_scores
),

complications AS (
  -- For each admission, flag cardiovascular and neurologic complications
  SELECT
    q.subject_id,
    q.hadm_id,
    q.anchor_age,
    q.gender,
    q.hospital_expire_flag,
    q.cci,
    q.cci_quartile,
    MAX(
      CASE
        -- Cardiovascular: MI, arrhythmia, heart failure, stroke
        WHEN (diag.icd_version = 10 AND (
          diag.icd_code LIKE 'I21%' OR -- MI
          diag.icd_code LIKE 'I50%' OR -- Heart failure
          diag.icd_code LIKE 'I48%' OR -- Atrial fibrillation
          diag.icd_code LIKE 'I63%' OR -- Stroke
          diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%' -- Hemorrhagic stroke
        ))
        OR (diag.icd_version = 9 AND (
          diag.icd_code LIKE '410%' OR -- MI
          diag.icd_code LIKE '428%' OR -- Heart failure
          diag.icd_code LIKE '427%' OR -- Arrhythmia
          diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%' -- Stroke
        ))
        THEN 1 ELSE 0 END
    ) AS cv_complication,
    MAX(
      CASE
        -- Neurologic: stroke, seizure, delirium
        WHEN (diag.icd_version = 10 AND (
          diag.icd_code LIKE 'I63%' OR -- Stroke
          diag.icd_code LIKE 'G40%' OR -- Epilepsy/seizure
          diag.icd_code LIKE 'F05%'    -- Delirium
        ))
        OR (diag.icd_version = 9 AND (
          diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%' OR -- Stroke
          diag.icd_code LIKE '345%' OR -- Epilepsy/seizure
          diag.icd_code LIKE '293.0%'  -- Delirium
        ))
        THEN 1 ELSE 0 END
    ) AS neuro_complication
  FROM
    quartiles q
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON q.hadm_id = diag.hadm_id
  GROUP BY
    q.subject_id, q.hadm_id, q.anchor_age, q.gender, q.hospital_expire_flag, q.cci, q.cci_quartile
)

SELECT
  cci_quartile,
  COUNT(*) AS n_admissions,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 3) AS in_hospital_mortality_rate,
  ROUND(SUM(cv_complication) / COUNT(*), 3) AS cardiovascular_complication_rate,
  ROUND(SUM(neuro_complication) / COUNT(*), 3) AS neurologic_complication_rate
FROM
  complications
GROUP BY
  cci_quartile
ORDER BY
  cci_quartile;