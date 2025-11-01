WITH SepsisAdmissions AS (
    -- Define a cohort of admissions with sepsis based on ICD codes,
    -- as the mimiciv_derived.sepsis3 table is inaccessible.
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- Using common ICD-10 codes for sepsis
        (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code LIKE 'R65.2%'))
),
QT_PROLONGING_DRUGS AS (
    SELECT 'Amiodarone' AS drug_name UNION ALL
    SELECT 'Haloperidol' UNION ALL
    SELECT 'Azithromycin' UNION ALL
    SELECT 'Ciprofloxacin' UNION ALL
    SELECT 'Ondansetron' UNION ALL
    SELECT 'Sotalol'
),
BLEEDING_RISK_DRUGS AS (
    SELECT 'Warfarin' AS drug_name UNION ALL
    SELECT 'Heparin' UNION ALL
    SELECT 'Aspirin' UNION ALL
    SELECT 'Clopidogrel' UNION ALL
    SELECT 'Rivaroxaban' UNION ALL
    SELECT 'Apixaban' UNION ALL
    SELECT 'Dabigatran'
),
-- Step 2: Identify the base cohort (male, 80-90, sepsis)
BaseCohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        SepsisAdmissions sa -- Replaced the MIMIC-IV derived sepsis3 table with our own derivation
        ON adm.hadm_id = sa.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 80 AND 90
),
-- Step 3: Identify active medications within the first 24 hours for the base cohort.
-- Uses a LEFT JOIN to ensure all base cohort admissions are included,
-- even if they have no prescriptions in the 24h window.
AdmissionsMedications AS (
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.admittime,
        bc.dischtime,
        bc.hospital_expire_flag,
        bc.los_days,
        p.drug, -- Will be NULL if no prescription matches the criteria
        -- Flag if the *specific* drug is a QT-prolonging drug
        CASE WHEN qd.drug_name IS NOT NULL THEN 1 ELSE 0 END AS is_qt_prolonging_drug_per_rx,
        -- Flag if the *specific* drug is a bleeding-risk drug
        CASE WHEN brd.drug_name IS NOT NULL THEN 1 ELSE 0 END AS is_bleeding_risk_drug_per_rx
    FROM
        BaseCohort bc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON bc.subject_id = p.subject_id
        AND bc.hadm_id = p.hadm_id
        -- Filter prescriptions to the first 24 hours, placed in ON clause to preserve non-matching admissions
        AND p.starttime BETWEEN bc.admittime AND DATETIME_ADD(bc.admittime, INTERVAL 24 HOUR)
    LEFT JOIN
        QT_PROLONGING_DRUGS qd
        ON LOWER(p.drug) LIKE CONCAT('%', LOWER(qd.drug_name), '%')
    LEFT JOIN
        BLEEDING_RISK_DRUGS brd
        ON LOWER(p.drug) LIKE CONCAT('%', LOWER(brd.drug_name), '%')
),
-- Step 4: Aggregate drug flags and calculate medication complexity score per admission
AdmissionSummary AS (
    SELECT
        hadm_id,
        subject_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        los_days,
        -- Check if ANY QT-prolonging drug was given for this HADM_ID
        MAX(is_qt_prolonging_drug_per_rx) AS received_qt_drug,
        -- Check if ANY bleeding-risk drug was given for this HADM_ID
        MAX(is_bleeding_risk_drug_per_rx) AS received_bleeding_drug,
        -- Medication complexity score: count of unique drugs within 24 hours.
        -- COUNT(DISTINCT drug) correctly handles NULLs when no drugs were prescribed in the window.
        COUNT(DISTINCT drug) AS med_complexity_score
    FROM
        AdmissionsMedications
    GROUP BY
        hadm_id, subject_id, admittime, dischtime, hospital_expire_flag, los_days
),
-- Step 5: Define patient groups and calculate percentile ranks
PatientGroupsWithRanks AS (
    SELECT
        hadm_id,
        subject_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        los_days,
        received_qt_drug,
        received_bleeding_drug,
        med_complexity_score,
        CASE
            WHEN received_qt_drug = 1 AND received_bleeding_drug = 1 THEN 'QT_and_Bleeding_Risk_Patients'
            ELSE 'Other_Sepsis_Patients'
        END AS patient_group,
        -- Calculate percentile rank for medication complexity score within each group
        PERCENT_RANK() OVER (PARTITION BY (CASE
                                            WHEN received_qt_drug = 1 AND received_bleeding_drug = 1 THEN 'QT_and_Bleeding_Risk_Patients'
                                            ELSE 'Other_Sepsis_Patients'
                                          END) ORDER BY med_complexity_score ASC) AS med_complexity_percentile_rank
    FROM
        AdmissionSummary
),
-- Step 6: Identify top quartile patients for LOS/mortality analysis
TopQuartilePatients AS (
    SELECT
        hadm_id,
        patient_group,
        los_days,
        hospital_expire_flag
    FROM
        PatientGroupsWithRanks
    WHERE
        med_complexity_percentile_rank >= 0.75 -- Top 25% in terms of medication complexity score
)
-- Step 7: Final results - Medication complexity distribution, percentile ranks, and LOS/Mortality for top quartile
SELECT
    pg.patient_group,
    -- General Medication Complexity Score Distribution for each group
    COUNT(DISTINCT pg.hadm_id) AS total_admissions_in_group,
    MIN(pg.med_complexity_score) AS min_med_complexity_score,
    MAX(pg.med_complexity_score) AS max_med_complexity_score,
    ROUND(AVG(pg.med_complexity_score), 2) AS avg_med_complexity_score,
    ROUND(STDDEV(pg.med_complexity_score), 2) AS stddev_med_complexity_score,

    -- Specific Percentile Scores for Medication Complexity Score within each group
    APPROX_QUANTILES(pg.med_complexity_score, 100)[OFFSET(25)] AS p25_med_complexity_score,
    APPROX_QUANTILES(pg.med_complexity_score, 100)[OFFSET(50)] AS p50_med_complexity_score,
    APPROX_QUANTILES(pg.med_complexity_score, 100)[OFFSET(75)] AS p75_med_complexity_score,

    -- LOS and Mortality for the TOP QUARTILE of medication complexity score *within each group*
    ROUND(AVG(tq.los_days), 2) AS avg_los_top_quartile,
    ROUND(SUM(tq.hospital_expire_flag) * 100.0 / COUNT(tq.hadm_id), 2) AS mortality_rate_top_quartile_percent
FROM
    PatientGroupsWithRanks pg
LEFT JOIN
    TopQuartilePatients tq
    ON pg.hadm_id = tq.hadm_id AND pg.patient_group = tq.patient_group
GROUP BY
    pg.patient_group
ORDER BY
    pg.patient_group;