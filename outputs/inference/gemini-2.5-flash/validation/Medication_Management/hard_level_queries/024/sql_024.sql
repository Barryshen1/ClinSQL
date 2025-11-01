WITH admissions_filtered AS (
    -- 1. Filter initial cohort: female patients, age 68-78
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 68 AND 78
),
multi_trauma_admissions AS (
    -- 2. Identify multi-trauma patients from the filtered admissions
    --    Using ICD-10 code 'T07' for "Unspecified multiple injuries"
    SELECT DISTINCT
        af.subject_id,
        af.hadm_id,
        af.admittime,
        af.dischtime,
        af.hospital_expire_flag,
        af.los_days
    FROM
        admissions_filtered AS af
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON af.hadm_id = di.hadm_id
    WHERE
        di.icd_version = 10 -- Ensure ICD-10 for 'T07'
        AND di.icd_code = 'T07' -- ICD-10 for Unspecified multiple injuries
),
serotonergic_med_flags AS (
    -- Identify admissions with a serotonergic drug prescribed within the first 24 hours
    -- This list of drugs should be clinically validated for real-world applications.
    SELECT
        pr.hadm_id, -- Grouping by hadm_id for distinct list, so subject_id isn't strictly needed here
        TRUE AS has_serotonergic_risk
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    INNER JOIN
        multi_trauma_admissions AS mta
        ON pr.hadm_id = mta.hadm_id AND pr.subject_id = mta.subject_id
    WHERE
        -- Only consider medications with a start time within the first 24 hours of admission
        pr.starttime BETWEEN mta.admittime AND DATETIME_ADD(mta.admittime, INTERVAL 24 HOUR)
        AND REGEXP_CONTAINS(UPPER(pr.drug),
            -- Common serotonergic agents (examples - not exhaustive). Pattern in uppercase for consistency with UPPER(pr.drug).
            'FLUOXETINE|SERTRALINE|CITALOPRAM|ESCITALOPRAM|PAROXETINE|VENLAFAXINE|DULOXETINE|TRAZODONE|MIRTAZAPINE|BUPROPION|AMITRIPTYLINE|NORTRIPTYLINE|TRAMADOL|FENTANYL|REMIFENTANIL|TAPENTADOL|MEPERIDINE|SUMATRIPTAN|ZOLMITRIPTAN|RIZATRIPTAN|ONDANSETRON|GRANISETRON|LINEZOLID|METHYLENE BLUE|DEXTROMETHORPHAN'
        )
    GROUP BY
        pr.hadm_id
),
first_24h_med_counts_cte AS (
    -- 3. Calculate first 24h medication complexity (distinct drugs)
    SELECT
        pr.hadm_id,
        COUNT(DISTINCT pr.drug) AS first_24h_med_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    INNER JOIN
        multi_trauma_admissions AS mta
        ON pr.hadm_id = mta.hadm_id AND pr.subject_id = mta.subject_id
    WHERE
        pr.starttime BETWEEN mta.admittime AND DATETIME_ADD(mta.admittime, INTERVAL 24 HOUR)
    GROUP BY
        pr.hadm_id
),
cohort_combined AS (
    -- Combine all patient-level data for the multi-trauma cohort
    SELECT
        mta.subject_id,
        mta.hadm_id,
        mta.admittime,
        mta.dischtime,
        mta.los_days,
        mta.hospital_expire_flag,
        -- Default to FALSE if no serotonergic meds found
        COALESCE(sm.has_serotonergic_risk, FALSE) AS has_serotonergic_risk,
        -- Default to 0 if no meds in 24h
        COALESCE(fmc.first_24h_med_count, 0) AS first_24h_med_count
    FROM
        multi_trauma_admissions AS mta
    LEFT JOIN
        serotonergic_med_flags AS sm
        ON mta.hadm_id = sm.hadm_id
    LEFT JOIN
        first_24h_med_counts_cte AS fmc
        ON mta.hadm_id = fmc.hadm_id
),
-- Calculate quartiles and percentiles based on medication complexity for the entire cohort *once*
final_cohort_with_complexity AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY first_24h_med_count ASC) AS med_complexity_quartile,
        PERCENT_RANK() OVER (ORDER BY first_24h_med_count ASC) AS med_complexity_percent_rank
    FROM
        cohort_combined
)
-- First part of the UNION ALL: Serotonergic interaction risk versus other multi-trauma patients
SELECT
    CASE
        WHEN hadm_data.has_serotonergic_risk IS TRUE THEN 'With Serotonergic Risk'
        ELSE 'Without Serotonergic Risk'
    END AS Analysis_Group,
    'Serotonergic Risk' AS Cohort_Type,
    COUNT(hadm_data.hadm_id) AS Num_Admissions,
    ROUND(AVG(hadm_data.first_24h_med_count), 2) AS Avg_Med_Complexity_Count,
    ROUND(AVG(hadm_data.med_complexity_percent_rank) * 100, 2) AS Avg_Med_Complexity_Percentile,
    ROUND(AVG(hadm_data.los_days), 2) AS Avg_LOS_Days,
    ROUND(SUM(CASE WHEN hadm_data.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_data.hadm_id), 2) AS Mortality_Rate_Percent
FROM
    final_cohort_with_complexity AS hadm_data
GROUP BY
    hadm_data.has_serotonergic_risk

UNION ALL

-- Second part of the UNION ALL: LOS and mortality for top quartile of medication complexity
SELECT
    'Top Quartile of Medication Complexity' AS Analysis_Group,
    'Top Quartile' AS Cohort_Type,
    COUNT(hadm_data.hadm_id) AS Num_Admissions,
    ROUND(AVG(hadm_data.first_24h_med_count), 2) AS Avg_Med_Complexity_Count,
    ROUND(AVG(hadm_data.med_complexity_percent_rank) * 100, 2) AS Avg_Med_Complexity_Percentile,
    ROUND(AVG(hadm_data.los_days), 2) AS Avg_LOS_Days,
    ROUND(SUM(CASE WHEN hadm_data.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_data.hadm_id), 2) AS Mortality_Rate_Percent
FROM
    final_cohort_with_complexity AS hadm_data
WHERE
    hadm_data.med_complexity_quartile = 4;