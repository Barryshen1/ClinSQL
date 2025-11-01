WITH all_admissions_ranked AS (
    -- Create a view of all admissions with the next admission time for each patient
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

hf_admissions AS (
    -- Identify the cohort of male patients, aged 40-50, with a Heart Failure diagnosis
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year + p.anchor_age) BETWEEN 40 AND 50
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
            WHERE dx.hadm_id = ad.hadm_id
            AND (
                dx.icd_code LIKE '428%'  -- ICD-9 for Heart Failure
                OR dx.icd_code LIKE 'I50%' -- ICD-10 for Heart Failure
            )
        )
),

med_complexity AS (
    -- Calculate a 7-day medication complexity score for each HF admission
    SELECT
        hf.hadm_id,
        COUNT(DISTINCT pr.drug) AS medication_complexity_score
    FROM hf_admissions AS hf
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        ON hf.hadm_id = pr.hadm_id
    WHERE
        pr.starttime BETWEEN hf.admittime AND DATETIME_ADD(hf.admittime, INTERVAL 7 DAY)
    GROUP BY hf.hadm_id
),

cohort_metrics AS (
    -- Combine all metrics: LOS, mortality, readmission flag, and med score
    SELECT
        hf.hadm_id,
        COALESCE(mc.medication_complexity_score, 0) AS med_score,
        DATETIME_DIFF(hf.dischtime, hf.admittime, DAY) AS los_days,
        hf.hospital_expire_flag,
        CASE
            WHEN DATETIME_DIFF(aar.next_admittime, hf.dischtime, DAY) BETWEEN 0 AND 30
                THEN 1
            ELSE 0
        END AS is_readmitted_30d
    FROM hf_admissions AS hf
    LEFT JOIN med_complexity AS mc
        ON hf.hadm_id = mc.hadm_id
    LEFT JOIN all_admissions_ranked AS aar
        ON hf.hadm_id = aar.hadm_id
),

cohort_quintiles AS (
    -- Stratify the cohort into quintiles based on the medication score
    SELECT
        *,
        NTILE(5) OVER (ORDER BY med_score) AS score_quintile
    FROM cohort_metrics
)

-- Final aggregation and reporting
SELECT
    score_quintile,
    COUNT(hadm_id) AS number_of_admissions,
    CONCAT(CAST(MIN(med_score) AS STRING), ' - ', CAST(MAX(med_score) AS STRING)) AS score_range,
    ROUND(AVG(los_days), 1) AS mean_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
    ROUND(AVG(is_readmitted_30d) * 100, 2) AS readmission_30d_pct
FROM cohort_quintiles
GROUP BY score_quintile
ORDER BY score_quintile;