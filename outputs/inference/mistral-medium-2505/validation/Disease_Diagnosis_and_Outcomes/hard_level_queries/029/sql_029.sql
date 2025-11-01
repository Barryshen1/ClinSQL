WITH
-- Define pneumonia ICD codes (example codes - adjust as needed)
pneumonia_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('J18.9', 'J18.1', 'J18.0', 'J15.9', 'J13', 'J12.9', 'J14', 'J16.9')
     OR (icd_version = 9 AND icd_code IN ('486', '482.9', '481', '480.9', '485', '483.8', '482.39'))
),

-- Get female patients aged 82-92 with pneumonia admissions
female_pneumonia_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod,
    -- Calculate age at admission (anchor_age is age at first admission)
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN pneumonia_codes pc ON d.icd_code = pc.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND a.admission_type != 'NEWBORN'  -- Exclude newborn admissions
),

-- Calculate composite risk score components
risk_score_components AS (
  SELECT
    fpp.subject_id,
    fpp.hadm_id,
    fpp.age_at_admission,
    fpp.hospital_expire_flag,
    fpp.deathtime,
    fpp.dod,
    -- Count of Charlson comorbidities (simplified example)
    COUNT(DISTINCT CASE WHEN d.icd_code IN (
      'E11.65', 'I10', 'I11.0', 'I25.10', 'I50.9', 'J44.9', 'N18.3', 'N18.4', 'N18.5', 'N18.6'
    ) THEN d.icd_code END) AS charlson_comorbidities,
    -- Example lab values (simplified - would need proper itemid mapping)
    MAX(CASE WHEN l.itemid IN (50885, 50912) THEN l.valuenum ELSE NULL END) AS max_creatinine,
    MAX(CASE WHEN l.itemid IN (50983, 50824) THEN l.valuenum ELSE NULL END) AS max_sodium
  FROM female_pneumonia_patients fpp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON fpp.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON fpp.hadm_id = l.hadm_id
  GROUP BY fpp.subject_id, fpp.hadm_id, fpp.age_at_admission, fpp.hospital_expire_flag, fpp.deathtime, fpp.dod
),

-- Calculate composite risk score (simplified example)
risk_scores AS (
  SELECT
    subject_id,
    hadm_id,
    age_at_admission,
    hospital_expire_flag,
    deathtime,
    dod,
    charlson_comorbidities,
    max_creatinine,
    max_sodium,
    -- Simple composite score (would need proper clinical validation)
    (age_at_admission * 0.1) +
    (charlson_comorbidities * 2) +
    (CASE WHEN max_creatinine > 2 THEN 5 ELSE 0 END) +
    (CASE WHEN max_sodium > 150 THEN 3 ELSE 0 END) AS composite_risk_score
  FROM risk_score_components
),

-- Add quintiles based on risk score
quintiles AS (
  SELECT
    r.*,
    NTILE(5) OVER (ORDER BY r.composite_risk_score) AS risk_quintile
  FROM risk_scores r
),

-- Calculate outcomes
outcomes AS (
  SELECT
    q.risk_quintile,
    COUNT(DISTINCT q.hadm_id) AS total_patients,
    -- 30-day mortality
    SUM(CASE
          WHEN q.hospital_expire_flag = 1
          OR (q.deathtime IS NOT NULL AND TIMESTAMP_DIFF(q.deathtime, a.admittime, DAY) <= 30)
          OR (q.dod IS NOT NULL AND TIMESTAMP_DIFF(q.dod, a.admittime, DAY) <= 30)
          THEN 1 ELSE 0
        END) AS deaths_within_30_days,
    -- Cardiovascular complications
    SUM(CASE
          WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code
            WHERE d.hadm_id = q.hadm_id
              AND di.icd_code IN ('I21', 'I22', 'I23', 'I24', 'I25', 'I50', 'I51', 'I60', 'I61', 'I62', 'I63')
          ) THEN 1 ELSE 0
        END) AS cv_complications,
    -- Neurologic complications
    SUM(CASE
          WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code
            WHERE d.hadm_id = q.hadm_id
              AND di.icd_code IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69')
          ) THEN 1 ELSE 0
        END) AS neuro_complications
  FROM quintiles q
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON q.hadm_id = a.hadm_id
  GROUP BY q.risk_quintile
),

-- Calculate median LOS for survivors
survivor_los AS (
  SELECT
    q.risk_quintile,
    PERCENTILE_CONT(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY), 0.5) OVER (PARTITION BY q.risk_quintile) AS median_los_survivors
  FROM quintiles q
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON q.hadm_id = a.hadm_id
  WHERE q.hospital_expire_flag = 0
    AND (q.deathtime IS NULL OR TIMESTAMP_DIFF(q.deathtime, a.admittime, DAY) > 30)
    AND (q.dod IS NULL OR TIMESTAMP_DIFF(q.dod, a.admittime, DAY) > 30)
  GROUP BY q.risk_quintile, q.hadm_id, a.admittime, a.dischtime
)

-- Final results
SELECT
  o.risk_quintile,
  o.total_patients,
  ROUND(100.0 * o.deaths_within_30_days / o.total_patients, 1) AS mortality_30day_pct,
  ROUND(100.0 * o.cv_complications / o.total_patients, 1) AS cv_complication_rate_pct,
  ROUND(100.0 * o.neuro_complications / o.total_patients, 1) AS neuro_complication_rate_pct,
  s.median_los_survivors
FROM outcomes o
JOIN survivor_los s ON o.risk_quintile = s.risk_quintile
GROUP BY o.risk_quintile, o.total_patients, o.deaths_within_30_days, o.cv_complications, o.neuro_complications, s.median_los_survivors
ORDER BY o.risk_quintile;