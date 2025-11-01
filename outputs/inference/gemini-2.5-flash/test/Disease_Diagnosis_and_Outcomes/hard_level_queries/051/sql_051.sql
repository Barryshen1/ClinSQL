WITH
  -- Define specific ICD codes relevant for acute pancreatitis
  acute_pancreatitis_icd AS (
    SELECT 'K850' AS code, CAST('10' AS INT64) AS version UNION ALL
    SELECT 'K851' AS code, CAST('10' AS INT64) AS version UNION ALL
    SELECT 'K852' AS code, CAST('10' AS INT64) AS version UNION ALL
    SELECT 'K853' AS code, CAST('10' AS INT64) AS version UNION ALL
    SELECT 'K858' AS code, CAST('10' AS INT64) AS version UNION ALL
    SELECT 'K859' AS code, CAST('10' AS INT64) AS version UNION ALL
    SELECT '5770' AS code, CAST('9' AS INT64) AS version
  ),
  -- Define specific ICD codes for major complications
  -- These codes are chosen to represent severe, acute complications
  major_complication_icd AS (
    -- Sepsis
    SELECT 'R6520' AS code, CAST('10' AS INT64) AS version UNION ALL -- Severe sepsis without septic shock
    SELECT 'R6521' AS code, CAST('10' AS INT64) AS version UNION ALL -- Severe sepsis with septic shock
    SELECT '99592' AS code, CAST('9' AS INT64) AS version UNION ALL  -- Severe sepsis
    SELECT '78552' AS code, CAST('9' AS INT64) AS version UNION ALL  -- Septic shock
    -- Acute Kidney Injury (AKI)
    SELECT 'N170' AS code, CAST('10' AS INT64) AS version UNION ALL -- Acute kidney failure with tubular necrosis
    SELECT 'N171' AS code, CAST('10' AS INT64) AS version UNION ALL -- Acute kidney failure with acute cortical necrosis
    SELECT 'N172' AS code, CAST('10' AS INT64) AS version UNION ALL -- Acute kidney failure with medullary necrosis
    SELECT 'N178' AS code, CAST('10' AS INT64) AS version UNION ALL -- Other acute kidney failure
    SELECT 'N179' AS code, CAST('10' AS INT64) AS version UNION ALL -- Acute kidney failure, unspecified
    SELECT '5845' AS code, CAST('9' AS INT64) AS version UNION ALL   -- Acute kidney failure, with lesion of tubular necrosis
    SELECT '5849' AS code, CAST('9' AS INT64) AS version UNION ALL   -- Acute kidney failure, unspecified
    -- Acute Respiratory Distress Syndrome (ARDS)
    SELECT 'J80' AS code, CAST('10' AS INT64) AS version UNION ALL   -- Acute respiratory distress syndrome
    SELECT '51882' AS code, CAST('9' AS INT64) AS version UNION ALL  -- Other pulmonary insufficiency, not elsewhere classified (common for ARDS in ICD-9)
    -- Disseminated Intravascular Coagulation (DIC)
    SELECT 'D65' AS code, CAST('10' AS INT64) AS version UNION ALL   -- Disseminated intravascular coagulation [DIC] and other coagulation defects
    SELECT '2866' AS code, CAST('9' AS INT64) AS version             -- Defibrination syndrome (DIC)
  ),
  -- Step 1: Identify the initial cohort of male patients aged 35-45 with acute pancreatitis
  initial_cohort AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        -- Calculate age at admission. anchor_year is the year of anchor_age.
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 35 AND 45
        -- Ensure the admission had an acute pancreatitis diagnosis
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_ap
            INNER JOIN acute_pancreatitis_icd ap_codes
                ON di_ap.icd_code = ap_codes.code
                AND di_ap.icd_version = ap_codes.version
            WHERE
                di_ap.hadm_id = ad.hadm_id
        )
  ),
  -- Step 2: Calculate total diagnosis count and major complication count for each admission
  admission_diagnoses_and_complications AS (
    SELECT
        ic.subject_id,
        ic.hadm_id,
        ic.hospital_expire_flag,
        ic.los_days,
        COUNT(DISTINCT di.icd_code) AS num_all_diagnoses, -- Total distinct diagnoses for the risk score
        COUNT(DISTINCT CASE
            WHEN mc.code IS NOT NULL THEN di.icd_code
            ELSE NULL
        END) AS num_major_complications, -- Count of distinct major complication types
        MAX(CASE
            WHEN mc.code IS NOT NULL THEN 1
            ELSE 0
        END) AS has_any_major_complication_flag -- Binary flag for major complication rate calculation
    FROM
        initial_cohort ic
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ic.hadm_id = di.hadm_id
    LEFT JOIN
        major_complication_icd mc
        ON di.icd_code = mc.code
        AND di.icd_version = mc.version
    GROUP BY
        ic.subject_id,
        ic.hadm_id,
        ic.hospital_expire_flag,
        ic.los_days
  ),
  -- Step 3: Calculate the risk score for each admission
  admission_risk_scores AS (
    SELECT
        subject_id,
        hadm_id,
        hospital_expire_flag,
        los_days,
        num_all_diagnoses,
        num_major_complications,
        has_any_major_complication_flag,
        (num_all_diagnoses + 5 * num_major_complications) AS risk_score
    FROM
        admission_diagnoses_and_complications
  ),
  -- Step 4: Assign risk score quartiles
  admissions_with_quartiles AS (
    SELECT
        subject_id,
        hadm_id,
        hospital_expire_flag,
        los_days,
        has_any_major_complication_flag,
        risk_score,
        NTILE(4) OVER (ORDER BY risk_score ASC) AS risk_quartile
    FROM
        admission_risk_scores
  )
-- Step 5: Aggregate results by quartile and overall
SELECT
    CAST(risk_quartile AS STRING) AS risk_stratum,
    COUNT(DISTINCT hadm_id) AS num_patients,
    SUM(hospital_expire_flag) AS num_deaths,
    (SUM(hospital_expire_flag) * 100.0 / COUNT(DISTINCT hadm_id)) AS in_hospital_mortality_rate_pct,
    SUM(has_any_major_complication_flag) AS num_admissions_with_major_complication,
    (SUM(has_any_major_complication_flag) * 100.0 / COUNT(DISTINCT hadm_id)) AS major_complication_rate_pct,
    -- Calculate median LOS only for survivors
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_survivor_los_days
FROM
    admissions_with_quartiles
GROUP BY
    risk_quartile

UNION ALL

-- Overall statistics
SELECT
    'Overall' AS risk_stratum,
    COUNT(DISTINCT hadm_id) AS num_patients,
    SUM(hospital_expire_flag) AS num_deaths,
    (SUM(hospital_expire_flag) * 100.0 / COUNT(DISTINCT hadm_id)) AS in_hospital_mortality_rate_pct,
    SUM(has_any_major_complication_flag) AS num_admissions_with_major_complication,
    (SUM(has_any_major_complication_flag) * 100.0 / COUNT(DISTINCT hadm_id)) AS major_complication_rate_pct,
    -- Calculate median LOS only for survivors
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_survivor_los_days
FROM
    admissions_with_quartiles
ORDER BY
    CASE WHEN risk_stratum = 'Overall' THEN 999 ELSE CAST(risk_stratum AS INT64) END; -- Order 'Overall' last;