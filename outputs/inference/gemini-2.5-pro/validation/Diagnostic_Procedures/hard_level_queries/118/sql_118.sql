WITH first_stays AS (
    -- Step 1: Identify the first ICU stay for female patients aged 44-54 with an AMI diagnosis
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
        FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON icu.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.hadm_id = adm.hadm_id
    WHERE
        icu.rn = 1  -- Filter for the first ICU stay only
        AND pat.gender = 'F'
        AND (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year + pat.anchor_age) BETWEEN 44 AND 54
        AND icu.hadm_id IN (
            -- Subquery to find hospital admissions with an AMI diagnosis
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE
                (icd_version = 9 AND icd_code LIKE '410%') -- ICD-9 for AMI
                OR
                (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%')) -- ICD-10 for AMI
        )
),
proc_counts AS (
    -- Step 2: Count procedures for each patient within the first 72 hours of their ICU stay
    SELECT
        fs.stay_id,
        fs.hospital_expire_flag,
        DATETIME_DIFF(fs.dischtime, fs.admittime, DAY) AS hospital_los_days,
        COUNT(pe.itemid) AS procedure_count
    FROM first_stays AS fs
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
        ON fs.stay_id = pe.stay_id
        AND pe.starttime BETWEEN fs.intime AND DATETIME_ADD(fs.intime, INTERVAL 72 HOUR)
    GROUP BY
        fs.stay_id,
        fs.hospital_expire_flag,
        hospital_los_days
),
proc_quartiles AS (
    -- Step 3: Stratify patients into quartiles based on their procedure count
    SELECT
        pc.procedure_count,
        pc.hospital_los_days,
        pc.hospital_expire_flag,
        NTILE(4) OVER (ORDER BY pc.procedure_count) AS quartile
    FROM proc_counts AS pc
)
-- Step 4: Calculate final metrics for each quartile
SELECT
    quartile,
    COUNT(*) AS n_per_quartile,
    ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
    ROUND(AVG(hospital_los_days), 2) AS mean_hospital_los_days,
    ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS in_hospital_mortality_pct
FROM proc_quartiles
GROUP BY quartile
ORDER BY quartile;