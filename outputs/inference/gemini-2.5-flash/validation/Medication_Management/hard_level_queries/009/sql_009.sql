WITH admissions_cohort AS (
    -- Step 1: Filter admissions for target population (female, age 84-94, with AKI diagnosis)
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        ad.hospital_expire_flag,
        pa.gender,
        pa.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 84 AND 94
    AND ad.hadm_id IN (
        SELECT DISTINCT di.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        WHERE
            (di.icd_version = 10 AND di.icd_code LIKE 'N17%') -- ICD-10 codes for Acute Kidney Injury
            OR (di.icd_version = 9 AND di.icd_code LIKE '584.%') -- ICD-9 codes for Acute Kidney Injury
    )
),
medication_data AS (
    -- Step 2: Calculate medication complexity score (distinct meds) and identify drug classes (anticoagulants, opioids)
    SELECT
        p.hadm_id,
        COUNT(DISTINCT p.drug) AS distinct_meds_count,
        MAX(
            CASE
                WHEN LOWER(p.drug) IN (
                    'warfarin', 'heparin', 'enoxaparin', 'dabigatran',
                    'rivaroxaban', 'apixaban', 'edoxaban'
                ) THEN 1
                ELSE 0
            END
        ) AS has_anticoagulant,
        MAX(
            CASE
                WHEN LOWER(p.drug) IN (
                    'morphine', 'fentanyl', 'oxycodone', 'hydromorphone',
                    'tramadol', 'codeine', 'hydrocodone', 'buprenorphine',
                    'methadone', 'meperidine', 'remifentanil', 'sufentanil',
                    'alfentanil'
                ) THEN 1
                ELSE 0
            END
        ) AS has_opioid
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    GROUP BY
        p.hadm_id
),
admission_details AS (
    -- Step 3: Combine admission and medication data, calculate LOS, and prepare for 30-day readmission flag
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        ac.hospital_expire_flag,
        -- Treat admissions with no prescriptions as having 0 distinct meds for complexity score
        COALESCE(med.distinct_meds_count, 0) AS distinct_meds_count,
        COALESCE(med.has_anticoagulant, 0) AS has_anticoagulant,
        COALESCE(med.has_opioid, 0) AS has_opioid,
        DATE_DIFF(ac.dischtime, ac.admittime, DAY) AS los_days,
        LEAD(ac.admittime) OVER (PARTITION BY ac.subject_id ORDER BY ac.admittime) AS next_admittime
    FROM
        admissions_cohort AS ac
    LEFT JOIN
        medication_data AS med
        ON ac.hadm_id = med.hadm_id
),
admission_with_readmission AS (
    -- Calculate 30-day readmission flag
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        distinct_meds_count,
        has_anticoagulant,
        has_opioid,
        los_days,
        CASE
            WHEN next_admittime IS NOT NULL
            AND DATE_DIFF(next_admittime, dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmission_30d_flag
    FROM
        admission_details
),
ranked_admissions AS (
    -- Step 4: Assign medication complexity quintile
    SELECT
        *,
        NTILE(5) OVER (ORDER BY distinct_meds_count) AS medication_complexity_quintile
    FROM
        admission_with_readmission
)
-- Step 5: Report per quintile: LOS, inpatient mortality %, 30-day readmission %, and anticoagulant–opioid coadministration counts
SELECT
    medication_complexity_quintile,
    COUNT(hadm_id) AS total_admissions,
    ROUND(AVG(los_days), 2) AS avg_los,
    ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(hadm_id)) * 100, 2) AS inpatient_mortality_percent,
    ROUND(SAFE_DIVIDE(SUM(readmission_30d_flag), COUNT(hadm_id)) * 100, 2) AS readmission_30d_percent,
    SUM(CASE WHEN has_anticoagulant = 1 AND has_opioid = 1 THEN 1 ELSE 0 END) AS coadministration_counts_anticoag_opioid
FROM
    ranked_admissions
WHERE
    medication_complexity_quintile IS NOT NULL -- Ensure only admissions assigned to a quintile are included
GROUP BY
    medication_complexity_quintile
ORDER BY
    medication_complexity_quintile;