WITH first_stays AS (
    SELECT
        hadm_id,
        stay_id,
        intime,
        los,
        ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY intime ASC) AS rn
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Step 2: Build the cohort of female patients aged 65-75 with pulmonary embolism on their first ICU stay
pe_cohort AS (
    SELECT DISTINCT
        adm.hadm_id,
        fs.stay_id,
        fs.intime,
        fs.los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        first_stays AS fs
        ON adm.hadm_id = fs.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        fs.rn = 1 -- Filter for the first ICU stay
        AND pat.gender = 'F'
        -- Calculate age at admission and filter
        AND (DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age) BETWEEN 65 AND 75
        -- Filter for Pulmonary Embolism diagnosis codes
        AND (
            (dx.icd_version = 9 AND dx.icd_code LIKE '4151%')
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I26%')
        )
),

-- Step 3: Count procedures for each patient within the first 72 hours of their ICU stay
patient_procedure_counts AS (
    SELECT
        pe.hadm_id,
        pe.los,
        pe.hospital_expire_flag,
        COUNT(proc.icd_code) AS procedure_count
    FROM
        pe_cohort AS pe
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON pe.hadm_id = proc.hadm_id
        -- Filter procedures to the first 72 hours of the ICU stay
        AND proc.chartdate BETWEEN DATE(pe.intime) AND DATE(DATETIME_ADD(pe.intime, INTERVAL 72 HOUR))
    GROUP BY
        pe.hadm_id, pe.los, pe.hospital_expire_flag
),

-- Step 4: Assign a quartile to each patient based on their procedure count
patient_quartiles AS (
    SELECT
        procedure_count,
        los,
        hospital_expire_flag,
        NTILE(4) OVER (ORDER BY procedure_count) AS quartile
    FROM
        patient_procedure_counts
)

-- Step 5: Aggregate metrics by quartile
SELECT
    quartile,
    COUNT(*) AS N,
    AVG(procedure_count) AS mean_procedure_count,
    AVG(los) AS mean_icu_los_days,
    AVG(hospital_expire_flag) * 100 AS hospital_mortality_pct
FROM
    patient_quartiles
GROUP BY
    quartile
ORDER BY
    quartile;