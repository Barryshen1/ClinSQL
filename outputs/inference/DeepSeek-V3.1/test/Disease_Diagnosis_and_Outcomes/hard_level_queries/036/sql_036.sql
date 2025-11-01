WITH pneumonia_patients AS (
    SELECT DISTINCT
        p.subject_id, 
        p.anchor_age,
        a.hadm_id,
        a.hospital_expire_flag,
        a.admittime,
        a.dischtime,
        a.deathtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 73 AND 83
        AND (
            (d.icd_version = 9 AND d.icd_code LIKE '486%') OR
            (d.icd_version = 10 AND d.icd_code LIKE 'J18%')
        )
),
elixhauser AS (
    -- Simplified: count number of Elixhauser categories present
    SELECT 
        hadm_id,
        COUNT(DISTINCT 
            CASE 
                WHEN icd_version = 9 AND icd_code IN ('39891','40201','40211','40291','40401','40403','40411','40413','40491','40493') THEN 'CHF'
                -- Note: This is a simplified example - a complete Elixhauser implementation would include all categories
                ELSE NULL
            END
        ) AS comorbidity_count
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),
cohort AS (
    SELECT 
        pp.*,
        COALESCE(e.comorbidity_count, 0) AS comorbidity_count
    FROM pneumonia_patients pp
    LEFT JOIN elixhauser e
        ON pp.hadm_id = e.hadm_id
),
percentile_calc AS (
    SELECT 
        APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS q3
    FROM cohort
),
top_quartile_cohort AS (
    SELECT *
    FROM cohort
    CROSS JOIN percentile_calc
    WHERE comorbidity_count >= q3
),
major_complications AS (
    SELECT 
        hadm_id,
        MAX(CASE 
            WHEN (icd_version = 9 AND (icd_code LIKE '995.91%' OR icd_code LIKE '995.92%')) OR
                 (icd_version = 10 AND (icd_code LIKE 'R65.20%' OR icd_code LIKE 'R65.21%')) THEN 1
            ELSE 0 
        END) AS sepsis,
        MAX(CASE 
            WHEN (icd_version = 9 AND icd_code LIKE '584%') OR
                 (icd_version = 10 AND icd_code LIKE 'N17%') THEN 1
            ELSE 0 
        END) AS renal_failure
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),
ventilation AS (
    SELECT 
        ce.hadm_id,
        MAX(CASE WHEN ce.itemid IN (223848, 223849) THEN 1 ELSE 0 END) AS mech_vent
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ce.stay_id = icu.stay_id
    GROUP BY ce.hadm_id
),
cohort_with_complications AS (
    SELECT 
        tqc.*,
        COALESCE(mc.sepsis, 0) AS sepsis,
        COALESCE(mc.renal_failure, 0) AS renal_failure,
        COALESCE(v.mech_vent, 0) AS mech_vent,
        CASE WHEN tqc.hospital_expire_flag = 1 THEN 
            DATE_DIFF(DATE(tqc.deathtime), DATE(tqc.admittime), DAY) 
        END AS survival_days
    FROM top_quartile_cohort tqc
    LEFT JOIN major_complications mc
        ON tqc.hadm_id = mc.hadm_id
    LEFT JOIN ventilation v
        ON tqc.hadm_id = v.hadm_id
)
SELECT 
    COUNT(*) AS total_patients,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS in_hospital_mortality_percent,
    ROUND(100.0 * SUM(CASE WHEN sepsis = 1 OR renal_failure = 1 OR mech_vent = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS major_complication_percent,
    APPROX_QUANTILES(survival_days, 100)[OFFSET(50)] AS median_survival_days
FROM cohort_with_complications;