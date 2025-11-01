WITH
-- Step 1: Identify the cohort of female admissions aged 84-94 with an AKI diagnosis.
aki_admissions AS (
    SELECT DISTINCT -- Use DISTINCT because a patient can have multiple AKI diagnoses for one admission
        p.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON ad.hadm_id = dx.hadm_id
    WHERE
        p.gender = 'F'
        AND (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year + p.anchor_age) BETWEEN 84 AND 94
        AND (dx.icd_code LIKE 'N17%' OR dx.icd_code LIKE '584%')
),

-- Step 2: Calculate 30-day readmission flag for the cohort patients.
-- This requires looking at all admissions for the patients in our cohort.
readmission_flags AS (
    SELECT
        hadm_id,
        CASE
            WHEN
                DATETIME_DIFF(
                    LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime),
                    dischtime,
                    DAY
                ) <= 30
                THEN 1
            ELSE 0
        END AS readmitted_30_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
    WHERE
        -- Restrict to patients who are in our cohort to improve performance
        subject_id IN (SELECT DISTINCT subject_id FROM aki_admissions)
),

-- Step 3: Calculate medication complexity score (count of unique drugs) for each admission in the cohort.
med_complexity AS (
    SELECT
        hadm_id,
        COUNT(DISTINCT drug) AS medication_complexity_score
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
        hadm_id IN (SELECT hadm_id FROM aki_admissions)
    GROUP BY
        hadm_id
),

-- Step 4: Calculate anticoagulant-opioid co-administration days.
-- First, find all days each relevant drug class was administered.
drug_admin_days AS (
    SELECT DISTINCT
        pr.hadm_id,
        admin_date,
        CASE
            WHEN LOWER(pr.drug) LIKE '%morphine%' OR LOWER(pr.drug) LIKE '%fentanyl%' OR LOWER(pr.drug) LIKE '%hydromorphone%' OR LOWER(pr.drug) LIKE '%oxycodone%' OR LOWER(pr.drug) LIKE '%methadone%' OR LOWER(pr.drug) LIKE '%tramadol%' OR LOWER(pr.drug) LIKE '%codeine%' OR LOWER(pr.drug) LIKE '%meperidine%' OR LOWER(pr.drug) LIKE '%remifentanil%' OR LOWER(pr.drug) LIKE '%sufentanil%'
                THEN 'Opioid'
            WHEN LOWER(pr.drug) LIKE '%heparin%' OR LOWER(pr.drug) LIKE '%warfarin%' OR LOWER(pr.drug) LIKE '%enoxaparin%' OR LOWER(pr.drug) LIKE '%dalteparin%' OR LOWER(pr.drug) LIKE '%apixaban%' OR LOWER(pr.drug) LIKE '%rivaroxaban%' OR LOWER(pr.drug) LIKE '%dabigatran%' OR LOWER(pr.drug) LIKE '%argatroban%' OR LOWER(pr.drug) LIKE '%bivalirudin%' OR LOWER(pr.drug) LIKE '%fondaparinux%'
                THEN 'Anticoagulant'
        END AS drug_class
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    CROSS JOIN
        UNNEST(GENERATE_DATE_ARRAY(DATE(pr.starttime), DATE(pr.stoptime), INTERVAL 1 DAY)) AS admin_date
    WHERE
        pr.hadm_id IN (SELECT hadm_id FROM aki_admissions)
        AND pr.starttime IS NOT NULL
        AND pr.stoptime IS NOT NULL
        AND pr.starttime < pr.stoptime
),

-- Then, count the days per admission where both drug classes were present.
coadmin_counts AS (
    SELECT
        hadm_id,
        COUNT(admin_date) AS coadmin_day_count
    FROM (
        SELECT
            hadm_id,
            admin_date
        FROM
            drug_admin_days
        WHERE
            drug_class IS NOT NULL
        GROUP BY
            hadm_id,
            admin_date
        HAVING
            COUNT(DISTINCT drug_class) = 2
    )
    GROUP BY
        hadm_id
),

-- Step 5: Combine all metrics and assign quintiles based on medication complexity.
quintiled_data AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY medication_complexity_score) AS med_complexity_quintile
    FROM (
        SELECT
            aki.hadm_id,
            aki.los,
            aki.hospital_expire_flag,
            COALESCE(rf.readmitted_30_days, 0) AS readmitted_30_days,
            COALESCE(mc.medication_complexity_score, 0) AS medication_complexity_score,
            COALESCE(cc.coadmin_day_count, 0) AS coadmin_day_count
        FROM
            aki_admissions AS aki
        LEFT JOIN
            readmission_flags AS rf
            ON aki.hadm_id = rf.hadm_id
        LEFT JOIN
            med_complexity AS mc
            ON aki.hadm_id = mc.hadm_id
        LEFT JOIN
            coadmin_counts AS cc
            ON aki.hadm_id = cc.hadm_id
    )
)

-- Step 6: Final aggregation by quintile.
SELECT
    med_complexity_quintile,
    COUNT(hadm_id) AS number_of_admissions,
    AVG(los) AS avg_los_days,
    AVG(hospital_expire_flag) * 100 AS inpatient_mortality_perc,
    AVG(readmitted_30_days) * 100 AS readmission_30_day_perc,
    SUM(coadmin_day_count) AS total_coadmin_days_count
FROM
    quintiled_data
GROUP BY
    med_complexity_quintile
ORDER BY
    med_complexity_quintile;