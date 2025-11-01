WITH
-- Step 1: Identify the cohort of male patients aged 35-45 with acute pancreatitis.
cohort AS (
    SELECT
        adm.hadm_id,
        adm.hospital_expire_flag,
        -- Calculate Length of Stay in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        -- Filter for male patients aged 35-45
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 35 AND 45
        -- Ensure the admission has a diagnosis of Acute Pancreatitis
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
            WHERE dx.hadm_id = adm.hadm_id
            AND (
                (dx.icd_version = 9 AND dx.icd_code = '5770')      -- ICD-9 for Acute Pancreatitis
                OR (dx.icd_version = 10 AND dx.icd_code LIKE 'K85%') -- ICD-10 for Acute Pancreatitis
            )
        )
),

-- Step 2: For each admission in the cohort, calculate the diagnosis count and flag for major complications.
hadm_features AS (
    SELECT
        c.hadm_id,
        c.hospital_expire_flag,
        c.los,
        COUNT(DISTINCT dx.icd_code) AS diagnosis_count,
        -- Flag is 1 if any major complication is found, 0 otherwise.
        MAX(CASE
            WHEN
                -- Acute Kidney Injury (AKI)
                (dx.icd_version = 9 AND dx.icd_code LIKE '584%')
                OR (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
                -- Acute Respiratory Distress Syndrome (ARDS)
                OR (dx.icd_version = 9 AND dx.icd_code = '51882')
                OR (dx.icd_version = 10 AND dx.icd_code = 'J80')
                -- Shock
                OR (dx.icd_version = 9 AND dx.icd_code LIKE '7855%')
                OR (dx.icd_version = 10 AND dx.icd_code LIKE 'R57%')
                -- Sepsis
                OR (dx.icd_version = 9 AND dx.icd_code IN ('99591', '99592'))
                OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'A40%' OR dx.icd_code LIKE 'A41%'))
                -- Pancreatic pseudocyst
                OR (dx.icd_version = 9 AND dx.icd_code = '5772')
                OR (dx.icd_version = 10 AND dx.icd_code = 'K863')
                -- Acute pancreatitis with necrosis (ICD-10 codes ending in '2')
                OR (dx.icd_version = 10 AND dx.icd_code LIKE 'K85%' AND SUBSTR(dx.icd_code, 5, 1) = '2')
            THEN 1
            ELSE 0
        END) AS major_complication_flag
    FROM cohort AS c
    -- Join with all diagnoses for the cohort admissions to calculate features
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON c.hadm_id = dx.hadm_id
    GROUP BY c.hadm_id, c.hospital_expire_flag, c.los
),

-- Step 3: Calculate the risk score and assign patients to quartiles.
risk_stratification AS (
    SELECT
        hadm_id,
        hospital_expire_flag,
        los,
        major_complication_flag,
        -- Risk Score = (diagnosis count) + 5 * (major complication flag)
        (diagnosis_count + 5 * major_complication_flag) AS risk_score,
        -- Stratify into 4 quartiles based on risk score
        NTILE(4) OVER (ORDER BY (diagnosis_count + 5 * major_complication_flag)) AS risk_quartile
    FROM hadm_features
)

-- Step 4: Calculate and report final metrics for each quartile and overall.
SELECT
    -- Use a CASE statement to label the overall rollup row
    CASE
        WHEN risk_quartile IS NULL THEN 'Overall'
        ELSE CAST(risk_quartile AS STRING)
    END AS risk_quartile,
    COUNT(hadm_id) AS number_of_patients,
    MIN(risk_score) AS min_risk_score,
    MAX(risk_score) AS max_risk_score,
    -- In-hospital mortality rate
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
    -- Major complication rate
    AVG(major_complication_flag) AS major_complication_rate,
    -- Calculate median LOS for survivors only
    APPROX_QUANTILES(
        CASE WHEN hospital_expire_flag = 0 THEN los END, 100
    )[OFFSET(50)] AS median_survivor_los_days
FROM risk_stratification
-- Use ROLLUP to get per-quartile stats and a grand total (overall)
GROUP BY ROLLUP(risk_quartile)
ORDER BY risk_quartile;