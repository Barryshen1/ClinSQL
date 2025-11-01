with a diagnosis of
-- acute myocardial infarction.
-- It then counts the number of distinct procedures performed in the first 24 hours of the ICU stay.
-- Finally, it stratifies the cohort by quartiles of this procedure count and reports the mean
-- procedure count, mean ICU length of stay, and hospital mortality percentage for each quartile.

WITH

-- 1. Identify hospital admissions with a diagnosis of Acute Myocardial Infarction (AMI)
ami_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for AMI start with 410
        SUBSTR(icd_code, 1, 3) = '410'
        -- ICD-10 codes for AMI start with I21 or I22 (subsequent MI)
        OR SUBSTR(icd_code, 1, 3) IN ('I21', 'I22')
),

-- 2. Define the patient cohort and count their distinct procedures in the first 24h of ICU stay
cohort_with_proc_counts AS (
    SELECT
        icu.stay_id,
        icu.los,
        adm.hospital_expire_flag,
        -- Count distinct procedures within the first 24 hours of the ICU stay.
        -- The LEFT JOIN ensures stays with 0 procedures are included and counted as 0.
        COUNT(DISTINCT proc.itemid) AS num_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON pat.subject_id = adm.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON adm.hadm_id = icu.hadm_id
    -- Filter for AMI admissions only
    JOIN ami_admissions AS ami
        ON adm.hadm_id = ami.hadm_id
    -- Left join to procedures to count them; filter for the first 24 hours
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS proc
        ON icu.stay_id = proc.stay_id
        AND proc.starttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 76 AND 86
    GROUP BY
        icu.stay_id,
        icu.los,
        adm.hospital_expire_flag
),

-- 3. Stratify the cohort into quartiles based on the number of procedures
quartiles AS (
    SELECT
        los,
        hospital_expire_flag,
        num_procedures,
        -- Use NTILE to create 4 groups (quartiles) based on procedure count
        NTILE(4) OVER (ORDER BY num_procedures) AS procedure_quartile
    FROM cohort_with_proc_counts
)

-- 4. Calculate final metrics for each quartile
SELECT
    procedure_quartile,
    AVG(num_procedures) AS mean_procedure_count,
    AVG(los) AS mean_icu_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_percent
FROM quartiles
GROUP BY procedure_quartile
ORDER BY procedure_quartile;