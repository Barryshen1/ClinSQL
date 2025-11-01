WITH cohort AS (
    -- Step 1: Identify the patient cohort: female inpatients aged 74-84
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 74 AND 84
),

meds_first_24h AS (
    -- Step 2: Get all medications administered in the first 24 hours of admission
    SELECT
        c.hadm_id,
        e.medication
    FROM
        cohort AS c
    JOIN
        `physionet-data.mimiciv_3_1_hosp.emar` AS e
        ON c.hadm_id = e.hadm_id
    WHERE
        e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
        AND e.medication IS NOT NULL
),

med_complexity_per_hadm AS (
    -- Step 3: Calculate medication complexity and flag specific drug classes for each admission
    SELECT
        hadm_id,
        COUNT(DISTINCT medication) AS med_count,
        -- Flag for QT-prolonging drugs
        (SUM(CASE
            WHEN LOWER(medication) LIKE '%amiodarone%' OR
                 LOWER(medication) LIKE '%sotalol%' OR
                 LOWER(medication) LIKE '%ondansetron%' OR
                 LOWER(medication) LIKE '%citalopram%' OR
                 LOWER(medication) LIKE '%escitalopram%' OR
                 LOWER(medication) LIKE '%haloperidol%' OR
                 LOWER(medication) LIKE '%quetiapine%' OR
                 LOWER(medication) LIKE '%methadone%' OR
                 LOWER(medication) LIKE '%levofloxacin%' OR
                 LOWER(medication) LIKE '%azithromycin%' OR
                 LOWER(medication) LIKE '%fluconazole%'
            THEN 1 ELSE 0 END) > 0) AS has_qt_drug,
        -- Flag for bleeding-risk drugs
        (SUM(CASE
            WHEN LOWER(medication) LIKE '%warfarin%' OR
                 LOWER(medication) LIKE '%heparin%' OR
                 LOWER(medication) LIKE '%enoxaparin%' OR
                 LOWER(medication) LIKE '%dalteparin%' OR
                 LOWER(medication) LIKE '%apixaban%' OR
                 LOWER(medication) LIKE '%rivaroxaban%' OR
                 LOWER(medication) LIKE '%dabigatran%' OR
                 LOWER(medication) LIKE '%aspirin%' OR
                 LOWER(medication) LIKE '%clopidogrel%' OR
                 LOWER(medication) LIKE '%ticagrelor%' OR
                 LOWER(medication) LIKE '%prasugrel%' OR
                 LOWER(medication) LIKE '%ibuprofen%' OR
                 LOWER(medication) LIKE '%naproxen%' OR
                 LOWER(medication) LIKE '%diclofenac%'
            THEN 1 ELSE 0 END) > 0) AS has_bleeding_risk_drug
    FROM
        meds_first_24h
    GROUP BY
        hadm_id
),

analysis_base AS (
    -- Step 4: Create the final base table for analysis by combining all metrics
    SELECT
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag,
        COALESCE(mc.med_count, 0) AS med_count,
        COALESCE(mc.has_qt_drug, FALSE) AS has_qt_drug,
        COALESCE(mc.has_bleeding_risk_drug, FALSE) AS has_bleeding_risk_drug,
        (icu.stay_id IS NOT NULL) AS is_icu,
        -- Rank complexity to find percentiles and quartiles
        PERCENT_RANK() OVER (ORDER BY COALESCE(mc.med_count, 0)) AS med_complexity_percentile,
        NTILE(4) OVER (ORDER BY COALESCE(mc.med_count, 0)) AS med_complexity_quartile
    FROM
        cohort AS c
    LEFT JOIN
        med_complexity_per_hadm AS mc
        ON c.hadm_id = mc.hadm_id
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON c.hadm_id = icu.hadm_id
)

-- Step 5: Calculate and present all final metrics from the analysis_base
SELECT
    -- Medication Complexity Distribution
    (SELECT AVG(med_count) FROM analysis_base) AS mean_medication_complexity,
    (SELECT MIN(med_count) FROM analysis_base) AS min_medication_complexity,
    (SELECT MAX(med_count) FROM analysis_base) AS max_medication_complexity,
    (SELECT STDDEV(med_count) FROM analysis_base) AS stddev_medication_complexity,

    -- Prevalence of Drug Classes
    (SELECT AVG(IF(has_qt_drug, 1, 0)) * 100 FROM analysis_base) AS prevalence_qt_prolonging_drugs_pct,
    (SELECT AVG(IF(has_bleeding_risk_drug, 1, 0)) * 100 FROM analysis_base) AS prevalence_bleeding_risk_drugs_pct,

    -- Mean Complexity Percentile
    (SELECT AVG(med_complexity_percentile) * 100 FROM analysis_base) AS mean_complexity_percentile,

    -- ICU Comparison
    (SELECT AVG(med_count) FROM analysis_base WHERE is_icu) AS mean_complexity_icu_patients,
    (SELECT AVG(med_count) FROM analysis_base WHERE NOT is_icu) AS mean_complexity_non_icu_patients,

    -- Top-Quartile Outcomes
    (SELECT AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) FROM analysis_base WHERE med_complexity_quartile = 4) AS top_quartile_mean_los_days,
    (SELECT STDDEV(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) FROM analysis_base WHERE med_complexity_quartile = 4) AS top_quartile_stddev_los_days,
    (SELECT AVG(hospital_expire_flag) * 100 FROM analysis_base WHERE med_complexity_quartile = 4) AS top_quartile_mortality_pct;