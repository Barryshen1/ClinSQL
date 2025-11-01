WITH AdmissionsCohort AS (
    -- Step 1: Define the target cohort - male inpatients aged 39-49
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        a.hospital_expire_flag,
        p.gender,
        p.anchor_age,
        -- Calculate Length of Stay in days
        TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
        -- Flag for in-hospital mortality
        CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 39 AND 49 -- Age at anchor_year, approximate age at admission
),
MedicationsFirst24H AS (
    -- Step 2: Identify medications prescribed within the first 24 hours of admission
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        ac.los_days,
        ac.mortality_flag,
        p.drug,
        -- Define flags for common QT-prolonging drugs
        MAX(CASE
            WHEN LOWER(p.drug) LIKE '%amiodarone%'
                OR LOWER(p.drug) LIKE '%haloperidol%'
                OR LOWER(p.drug) LIKE '%azithromycin%'
                OR LOWER(p.drug) LIKE '%citalopram%'
                OR LOWER(p.drug) LIKE '%levofloxacin%'
                OR LOWER(p.drug) LIKE '%ondansetron%'
                OR LOWER(p.drug) LIKE '%sotalol%'
                OR LOWER(p.drug) LIKE '%quinidine%'
            THEN 1 ELSE 0
        END) AS is_qt_prolonging_drug_item,
        -- Define flags for common bleeding-risk drugs (anticoagulants/antiplatelets)
        MAX(CASE
            WHEN LOWER(p.drug) LIKE '%warfarin%'
                OR LOWER(p.drug) LIKE '%heparin%'
                OR LOWER(p.drug) LIKE '%enoxaparin%'
                OR LOWER(p.drug) LIKE '%clopidogrel%'
                OR LOWER(p.drug) LIKE '%ticagrelor%'
                OR LOWER(p.drug) LIKE '%dabigatran%'
                OR LOWER(p.drug) LIKE '%rivaroxaban%'
                OR LOWER(p.drug) LIKE '%apixaban%'
            THEN 1 ELSE 0
        END) AS is_bleeding_risk_drug_item
    FROM
        AdmissionsCohort ac
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON ac.subject_id = p.subject_id AND ac.hadm_id = p.hadm_id
    WHERE
        p.starttime IS NULL -- Include patients with no prescriptions in first 24h
        OR (p.starttime >= ac.admittime AND p.starttime <= TIMESTAMP_ADD(ac.admittime, INTERVAL 24 HOUR))
    GROUP BY
        ac.subject_id, ac.hadm_id, ac.admittime, ac.dischtime, ac.los_days, ac.mortality_flag, p.drug
),
AdmissionMedSummary AS (
    -- Step 3: Summarize medication complexity and exposure flags per admission
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        los_days,
        mortality_flag,
        COUNT(DISTINCT drug) AS medication_complexity, -- Count of distinct medications
        MAX(is_qt_prolonging_drug_item) AS had_qt_prolonging_drug, -- 1 if any QT prolonging drug was given
        MAX(is_bleeding_risk_drug_item) AS had_bleeding_risk_drug -- 1 if any bleeding risk drug was given
    FROM
        MedicationsFirst24H
    GROUP BY
        subject_id, hadm_id, admittime, dischtime, los_days, mortality_flag
),
RankedAdmissions AS (
    -- Step 4: Calculate percentile rank for medication complexity across the cohort
    SELECT
        *,
        PERCENT_RANK() OVER (ORDER BY medication_complexity) AS complexity_percent_rank
    FROM
        AdmissionMedSummary
)
-- Step 5: Perform final comparisons for each defined group
-- Comparison Group 1: General Inpatients (entire cohort)
SELECT
    'General Inpatients' AS comparison_group,
    COUNT(DISTINCT hadm_id) AS patient_count,
    ROUND(AVG(medication_complexity), 2) AS avg_medication_complexity,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(SUM(mortality_flag) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS mortality_rate_percent,
    ROUND(AVG(complexity_percent_rank) * 100, 2) AS avg_complexity_percentile_rank
FROM
    RankedAdmissions
GROUP BY 1

UNION ALL

-- Comparison Group 2: Patients exposed to QT-Prolonging Drugs
SELECT
    'QT-Prolonging Drug Exposure' AS comparison_group,
    COUNT(DISTINCT hadm_id) AS patient_count,
    ROUND(AVG(medication_complexity), 2) AS avg_medication_complexity,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(SUM(mortality_flag) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS mortality_rate_percent,
    ROUND(AVG(complexity_percent_rank) * 100, 2) AS avg_complexity_percentile_rank
FROM
    RankedAdmissions
WHERE
    had_qt_prolonging_drug = 1
GROUP BY 1

UNION ALL

-- Comparison Group 3: Patients exposed to Bleeding-Risk Drugs
SELECT
    'Bleeding-Risk Drug Exposure' AS comparison_group,
    COUNT(DISTINCT hadm_id) AS patient_count,
    ROUND(AVG(medication_complexity), 2) AS avg_medication_complexity,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(SUM(mortality_flag) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS mortality_rate_percent,
    ROUND(AVG(complexity_percent_rank) * 100, 2) AS avg_complexity_percentile_rank
FROM
    RankedAdmissions
WHERE
    had_bleeding_risk_drug = 1
GROUP BY 1

UNION ALL

-- Comparison Group 4: Patients in the Top Quartile of Medication Complexity
SELECT
    'Top Quartile (Medication Complexity)' AS comparison_group, -- Report specific LOS and mortality for this group
    COUNT(DISTINCT hadm_id) AS patient_count,
    ROUND(AVG(medication_complexity), 2) AS avg_medication_complexity,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(SUM(mortality_flag) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS mortality_rate_percent,
    ROUND(AVG(complexity_percent_rank) * 100, 2) AS avg_complexity_percentile_rank
FROM
    RankedAdmissions
WHERE
    complexity_percent_rank >= 0.75 -- Top 25% of medication complexity
GROUP BY 1
ORDER BY comparison_group;