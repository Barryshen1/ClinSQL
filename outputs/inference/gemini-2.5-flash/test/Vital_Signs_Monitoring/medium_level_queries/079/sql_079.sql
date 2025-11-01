WITH icu_patients_filtered AS (
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 40 AND 50
),
-- Step 2: Extract SBP measurements within the first 48 hours of ICU stay
-- Item IDs for Systolic Blood Pressure:
-- 220050: Arterial Blood Pressure systolic
-- 220179: BP Systolic (Non-Invasive)
sbp_measurements AS (
    SELECT
        ipf.stay_id,
        ce.valuenum AS sbp_value
    FROM
        icu_patients_filtered ipf
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ipf.subject_id = ce.subject_id
        AND ipf.hadm_id = ce.hadm_id
        AND ipf.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (220050, 220179)
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN ipf.intime AND TIMESTAMP_ADD(ipf.intime, INTERVAL 48 HOUR)
),
-- Step 3: Calculate per-stay mean SBP for the first 48 hours
per_stay_mean_sbp AS (
    SELECT
        stay_id,
        AVG(sbp_value) AS mean_sbp_48h
    FROM
        sbp_measurements
    GROUP BY
        stay_id
    HAVING AVG(sbp_value) IS NOT NULL -- Ensure only stays with at least one SBP value are included
),
-- Step 4: Categorize the mean SBP and assign an order for presentation
categorized_sbp AS (
    SELECT
        ps.stay_id,
        ps.mean_sbp_48h,
        CASE
            WHEN ps.mean_sbp_48h < 140 THEN '<140 mmHg'
            WHEN ps.mean_sbp_48h BETWEEN 140 AND 159 THEN '140-159 mmHg'
            WHEN ps.mean_sbp_48h >= 160 THEN '>=160 mmHg'
            ELSE 'Unknown'
        END AS sbp_category,
        CASE
            WHEN ps.mean_sbp_48h < 140 THEN 1
            WHEN ps.mean_sbp_48h BETWEEN 140 AND 159 THEN 2
            WHEN ps.mean_sbp_48h >= 160 THEN 3
            ELSE 99
        END AS sbp_category_order
    FROM
        per_stay_mean_sbp ps
),
-- Step 5: Identify Myocardial Infarction (MI) diagnoses for each admission
mi_diagnoses AS (
    SELECT DISTINCT
        hadm_id,
        1 AS has_mi_diagnosis
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND icd_code LIKE '410%') -- ICD-9 for Acute MI
        OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I21') -- ICD-10 for Acute MI
),
-- Step 6: Combine all information for the final cohort
final_cohort_data AS (
    SELECT
        cs.stay_id,
        cs.sbp_category,
        cs.sbp_category_order,
        COALESCE(md.has_mi_diagnosis, 0) AS has_mi
    FROM
        categorized_sbp cs
    INNER JOIN
        icu_patients_filtered ipf
        ON cs.stay_id = ipf.stay_id
    LEFT JOIN
        mi_diagnoses md
        ON ipf.hadm_id = md.hadm_id
)
-- Final aggregation and reporting
SELECT
    sbp_category,
    COUNT(DISTINCT stay_id) AS num_icu_stays,
    ROUND(COUNT(DISTINCT stay_id) * 100.0 / (SELECT COUNT(DISTINCT stay_id) FROM final_cohort_data), 2) AS percent_of_total_stays,
    ROUND(SUM(has_mi) * 100.0 / COUNT(DISTINCT stay_id), 2) AS mi_rate_per_category
FROM
    final_cohort_data
GROUP BY
    sbp_category, sbp_category_order
ORDER BY
    sbp_category_order;