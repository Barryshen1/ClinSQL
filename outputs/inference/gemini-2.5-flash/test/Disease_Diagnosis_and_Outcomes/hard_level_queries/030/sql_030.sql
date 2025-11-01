WITH ugib_admissions AS (
    -- Step 1: Identify all hospital admissions for male patients aged 64-74
    -- that have an upper GI bleeding diagnosis
    SELECT
        admi.subject_id,
        admi.hadm_id,
        admi.admittime,
        admi.dischtime,
        admi.deathtime,
        admi.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pat
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` admi
        ON pat.subject_id = admi.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 64 AND 74
        -- Ensure this admission has at least one upper GI bleeding diagnosis (ICD-10 codes)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.hadm_id = admi.hadm_id
                AND di.icd_version = 10
                AND (
                    di.icd_code LIKE 'K92.0%' OR -- Hematemesis
                    di.icd_code LIKE 'K92.1%' OR -- Melena
                    di.icd_code LIKE 'K92.2%' OR -- Gastrointestinal hemorrhage, unspecified
                    di.icd_code LIKE 'K25.0%' OR -- Acute gastric ulcer with hemorrhage
                    di.icd_code LIKE 'K25.2%' OR -- Acute gastric ulcer with hemorrhage and perforation
                    di.icd_code LIKE 'K25.4%' OR -- Chronic gastric ulcer with hemorrhage
                    di.icd_code LIKE 'K25.6%' OR -- Chronic gastric ulcer with hemorrhage and perforation
                    di.icd_code LIKE 'K26.0%' OR -- Acute duodenal ulcer with hemorrhage
                    di.icd_code LIKE 'K26.2%' OR -- Acute duodenal ulcer with hemorrhage and perforation
                    di.icd_code LIKE 'K26.4%' OR -- Chronic duodenal ulcer with hemorrhage
                    di.icd_code LIKE 'K26.6%' OR -- Chronic duodenal ulcer with hemorrhage and perforation
                    di.icd_code LIKE 'I85.01%' OR -- Esophageal varices with bleeding
                    di.icd_code LIKE 'I85.11%'    -- Secondary esophageal varices with bleeding
                )
        )
),
admission_details_with_metrics AS (
    -- Step 2: Calculate diagnosis count and major complication flag for each identified admission
    SELECT
        uga.subject_id,
        uga.hadm_id,
        uga.admittime,
        uga.dischtime,
        uga.deathtime,
        uga.hospital_expire_flag,
        COUNT(DISTINCT di.icd_code) AS diagnosis_count,
        MAX(CASE
            WHEN di.icd_version = 10 AND (
                -- Major complication codes: Sepsis & Acute Kidney Injury
                di.icd_code LIKE 'A40.%' OR -- Sepsis
                di.icd_code LIKE 'A41.%' OR -- Sepsis
                di.icd_code LIKE 'R65.2%' OR -- Severe sepsis, unspecified
                di.icd_code LIKE 'N17.%'     -- Acute kidney injury
            ) THEN 1
            ELSE 0
        END) AS major_complication_flag
    FROM
        ugib_admissions uga
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON uga.hadm_id = di.hadm_id
    GROUP BY
        uga.subject_id, uga.hadm_id, uga.admittime, uga.dischtime, uga.deathtime, uga.hospital_expire_flag
),
patient_scores_and_outcomes AS (
    -- Step 3: Calculate composite risk score and other outcome flags/LOS for each admission
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        adm.hospital_expire_flag,
        adm.diagnosis_count,
        adm.major_complication_flag,
        (adm.diagnosis_count + 20 * adm.major_complication_flag) AS composite_risk_score,
        -- Flag for 30-day mortality
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 1 -- Died during hospital stay
            WHEN adm.deathtime IS NOT NULL AND adm.deathtime <= DATETIME_ADD(adm.admittime, INTERVAL 30 DAY) THEN 1
            ELSE 0
        END AS mortality_30_day_flag,
        -- Length of Stay in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM
        admission_details_with_metrics adm
),
ranked_admissions AS (
    -- Step 4: Assign quintiles based on the composite risk score
    SELECT
        psa.*,
        NTILE(5) OVER (ORDER BY composite_risk_score) AS risk_quintile
    FROM
        patient_scores_and_outcomes psa
)
-- Step 5: Aggregate results by risk quintile
SELECT
    risk_quintile,
    COUNT(DISTINCT hadm_id) AS n,
    ROUND(AVG(composite_risk_score), 2) AS mean_score,
    ROUND(SUM(mortality_30_day_flag) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS `30_day_mortality_perc`,
    ROUND(SUM(major_complication_flag) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS major_complication_perc,
    ROUND(APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END, 2)[OFFSET(1)], 2) AS median_los_survivors_days
FROM
    ranked_admissions
GROUP BY
    risk_quintile
ORDER BY
    risk_quintile;