WITH pe_cohort_admissions AS (
    -- Step 1: Identify the target cohort (Women, age 64-74, with PE diagnosis)
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 64 AND 74
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dicd
            WHERE
                dicd.subject_id = adm.subject_id
                AND dicd.hadm_id = adm.hadm_id
                AND (
                    (dicd.icd_version = 10 AND dicd.icd_code LIKE 'I26%') -- ICD-10 for Pulmonary Embolism
                    OR (dicd.icd_version = 9 AND dicd.icd_code LIKE '415.1%') -- ICD-9 for Pulmonary Embolism
                )
        )
),
med_complexity_scores AS (
    -- Step 2: Calculate medication complexity (distinct meds in first 24 hours) for the cohort
    SELECT
        pca.hadm_id,
        COUNT(DISTINCT emar.medication) AS med_complexity_score
    FROM pe_cohort_admissions AS pca
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS emar
        ON pca.subject_id = emar.subject_id AND pca.hadm_id = emar.hadm_id
    WHERE
        emar.charttime BETWEEN pca.admittime AND DATETIME_ADD(pca.admittime, INTERVAL 24 HOUR)
    GROUP BY
        pca.hadm_id
),
admissions_with_readmission_flag AS (
    -- Step 3: Determine 30-day readmission status for each admission in the cohort
    SELECT
        pca.subject_id,
        pca.hadm_id,
        pca.admittime,
        pca.dischtime,
        pca.hospital_expire_flag,
        LEAD(pca.admittime) OVER (PARTITION BY pca.subject_id ORDER BY pca.admittime) AS next_admittime
    FROM pe_cohort_admissions AS pca
),
final_cohort_data AS (
    -- Step 4: Combine all calculated metrics and assign tertiles
    SELECT
        a.subject_id,
        a.hadm_id,
        mcs.med_complexity_score,
        (DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS los_days,
        a.hospital_expire_flag,
        CASE
            WHEN a.next_admittime IS NOT NULL
                 AND DATETIME_DIFF(a.next_admittime, a.dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END AS readmit_30d_flag
    FROM admissions_with_readmission_flag AS a
    INNER JOIN med_complexity_scores AS mcs
        ON a.hadm_id = mcs.hadm_id
),
cohort_tertiles AS (
    -- Step 5: Assign tertiles based on medication complexity score
    SELECT
        *,
        NTILE(3) OVER (ORDER BY med_complexity_score) AS med_complexity_tertile
    FROM final_cohort_data
)
-- Step 6: Final aggregation to report desired statistics by tertile
SELECT
    med_complexity_tertile,
    COUNT(DISTINCT hadm_id) AS admissions_count,
    MIN(med_complexity_score) AS min_med_score_range,
    MAX(med_complexity_score) AS max_med_score_range,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(SUM(CAST(hospital_expire_flag AS BIGNUMERIC)) * 100.0 / COUNT(hadm_id), 2) AS mortality_percent,
    ROUND(SUM(CAST(readmit_30d_flag AS BIGNUMERIC)) * 100.0 / COUNT(hadm_id), 2) AS readmission_30d_percent
FROM cohort_tertiles
GROUP BY
    med_complexity_tertile
ORDER BY
    med_complexity_tertile;