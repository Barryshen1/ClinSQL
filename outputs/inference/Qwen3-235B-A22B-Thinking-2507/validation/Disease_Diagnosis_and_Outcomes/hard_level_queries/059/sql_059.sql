WITH dka_codes AS (
  SELECT icd_code, icd_version
  FROM UNNEST([
    STRUCT('25010' AS icd_code, 9 AS icd_version),
    ('25011', 9),
    ('25012', 9),
    ('25013', 9),
    ('E1010', 10),
    ('E1011', 10),
    ('E1110', 10),
    ('E1111', 10),
    ('E1310', 10),
    ('E1311', 10),
    ('E1410', 10),
    ('E1411', 10)
  ]) 
),
aki_codes AS (
  SELECT icd_code, icd_version
  FROM UNNEST([
    STRUCT('5845' AS icd_code, 9 AS icd_version),
    ('5846', 9),
    ('5847', 9),
    ('5848', 9),
    ('5849', 9),
    ('N170', 10),
    ('N171', 10),
    ('N172', 10),
    ('N178', 10),
    ('N179', 10)
  ])
),
ards_codes AS (
  SELECT icd_code, icd_version
  FROM UNNEST([
    STRUCT('51882' AS icd_code, 9 AS icd_version),
    ('J80', 10)
  ])
),
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 59 AND 69
),
dka_patients AS (
  SELECT DISTINCT
    pa.subject_id,
    pa.hadm_id
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN dka_codes dc
    ON di.icd_code = dc.icd_code AND di.icd_version = dc.icd_version
),
general_patients AS (
  SELECT
    pa.subject_id,
    pa.hadm_id
  FROM patient_admissions pa
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    INNER JOIN dka_codes dc
      ON di.icd_code = dc.icd_code AND di.icd_version = dc.icd_version
    WHERE pa.hadm_id = di.hadm_id
  )
),
dka_patient_metrics AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    -- 30-day mortality
    CASE WHEN pa.dod IS NOT NULL 
              AND DATETIME_DIFF(CAST(pa.dod AS DATETIME), pa.admittime, DAY) <= 30 
         THEN 1 ELSE 0 END AS mortality_30d,
    -- AKI flag
    MAX(CASE WHEN di.icd_code IN (SELECT icd_code FROM aki_codes WHERE icd_version = di.icd_version) 
             THEN 1 ELSE 0 END) AS has_aki,
    -- ARDS flag
    MAX(CASE WHEN di.icd_code IN (SELECT icd_code FROM ards_codes WHERE icd_version = di.icd_version) 
             THEN 1 ELSE 0 END) AS has_ards,
    -- LOS in days (fixed modulo syntax)
    DATETIME_DIFF(pa.dischtime, pa.admittime, DAY) + 
      MOD(DATETIME_DIFF(pa.dischtime, pa.admittime, HOUR), 24) / 24.0 AS los,
    -- Hospital survivor flag
    CASE WHEN pa.hospital_expire_flag = 0 THEN 1 ELSE 0 END AS is_hospital_survivor,
    -- Simplified Charlson Comorbidity Index
    COALESCE(SUM(CASE 
          WHEN di.icd_code IN ('4019', 'I10') THEN 1
          WHEN di.icd_code IN ('4280', 'I509') THEN 2
          WHEN di.icd_code IN ('5859', 'N189') THEN 2
          WHEN di.icd_code IN ('25000', 'E119') THEN 1
          WHEN di.icd_code IN ('172', 'C43') THEN 6
          ELSE 0 
        END), 0) AS cci
  FROM patient_admissions pa
  INNER JOIN dka_patients dp
    ON pa.subject_id = dp.subject_id AND pa.hadm_id = dp.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  GROUP BY pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime, pa.dod, pa.hospital_expire_flag
),
general_patient_metrics AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    -- 30-day mortality
    CASE WHEN pa.dod IS NOT NULL 
              AND DATETIME_DIFF(CAST(pa.dod AS DATETIME), pa.admittime, DAY) <= 30 
         THEN 1 ELSE 0 END AS mortality_30d,
    -- AKI flag
    MAX(CASE WHEN di.icd_code IN (SELECT icd_code FROM aki_codes WHERE icd_version = di.icd_version) 
             THEN 1 ELSE 0 END) AS has_aki,
    -- ARDS flag
    MAX(CASE WHEN di.icd_code IN (SELECT icd_code FROM ards_codes WHERE icd_version = di.icd_version) 
             THEN 1 ELSE 0 END) AS has_ards,
    -- LOS in days (fixed modulo syntax)
    DATETIME_DIFF(pa.dischtime, pa.admittime, DAY) + 
      MOD(DATETIME_DIFF(pa.dischtime, pa.admittime, HOUR), 24) / 24.0 AS los,
    -- Hospital survivor flag
    CASE WHEN pa.hospital_expire_flag = 0 THEN 1 ELSE 0 END AS is_hospital_survivor,
    -- Simplified Charlson Comorbidity Index
    COALESCE(SUM(CASE 
          WHEN di.icd_code IN ('4019', 'I10') THEN 1
          WHEN di.icd_code IN ('4280', 'I509') THEN 2
          WHEN di.icd_code IN ('5859', 'N189') THEN 2
          WHEN di.icd_code IN ('25000', 'E119') THEN 1
          WHEN di.icd_code IN ('172', 'C43') THEN 6
          ELSE 0 
        END), 0) AS cci
  FROM patient_admissions pa
  INNER JOIN general_patients gp
    ON pa.subject_id = gp.subject_id AND pa.hadm_id = gp.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  GROUP BY pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime, pa.dod, pa.hospital_expire_flag
),
dka_summary AS (
  SELECT
    COUNT(*) AS n_dka,
    AVG(mortality_30d) AS mortality_30d_rate,
    AVG(has_aki) AS aki_rate,
    AVG(has_ards) AS ards_rate,
    AVG(CASE WHEN is_hospital_survivor = 1 THEN los END) AS survivor_los,
    AVG(cci) AS mean_cci
  FROM dka_patient_metrics
),
general_summary AS (
  SELECT
    COUNT(*) AS n_general,
    AVG(mortality_30d) AS mortality_30d_rate,
    AVG(has_aki) AS aki_rate,
    AVG(has_ards) AS ards_rate,
    AVG(CASE WHEN is_hospital_survivor = 1 THEN los END) AS survivor_los,
    AVG(cci) AS mean_cci
  FROM general_patient_metrics
),
cci_percentile AS (
  SELECT
    dka.mean_cci AS dka_mean_cci,
    COUNTIF(gpm.cci <= dka.mean_cci) * 100.0 / COUNT(*) AS cci_percentile
  FROM general_patient_metrics gpm
  CROSS JOIN dka_summary dka
)
SELECT
  'DKA Group' AS group_type,
  n_dka AS patient_count,
  mortality_30d_rate,
  aki_rate,
  ards_rate,
  survivor_los,
  mean_cci AS mean_risk_score,
  NULL AS cci_percentile
FROM dka_summary

UNION ALL

SELECT
  'General Inpatients' AS group_type,
  n_general AS patient_count,
  mortality_30d_rate,
  aki_rate,
  ards_rate,
  survivor_los,
  mean_cci AS mean_risk_score,
  NULL AS cci_percentile
FROM general_summary

UNION ALL

SELECT
  'DKA Risk Score Percentile in General Population' AS group_type,
  NULL AS patient_count,
  NULL AS mortality_30d_rate,
  NULL AS aki_rate,
  NULL AS ards_rate,
  NULL AS survivor_los,
  (SELECT dka_mean_cci FROM cci_percentile) AS mean_risk_score,
  (SELECT cci_percentile FROM cci_percentile) AS cci_percentile;