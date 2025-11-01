WITH all_male_cabg_admissions AS (
    -- Step 1: Identify all hospital admissions for CABG procedures for all male patients.
    -- This allows us to correctly identify the very first one for each patient later on.
    SELECT DISTINCT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        -- Calculate age at admission as an integer value
        (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc ON a.hadm_id = proc.hadm_id
    WHERE
        p.gender = 'M'
        -- Filter for CABG procedures using ICD-9 and ICD-10 codes
        AND (
            (proc.icd_version = 9 AND proc.icd_code LIKE '36.1%')
            OR (proc.icd_version = 10 AND proc.icd_code LIKE '021%')
        )
),
ranked_admissions AS (
    -- Step 2: Rank all CABG admissions chronologically for each patient.
    SELECT
        hadm_id,
        age_at_admission,
        ROW_NUMBER() OVER(PARTITION BY subject_id ORDER BY admittime ASC) as admission_rank
    FROM
        all_male_cabg_admissions
),
first_cabg_admissions_in_age_range AS (
    -- Step 3: Filter for the first admission (rank=1) and ensure it falls within the specified age range.
    -- This defines the final cohort of interest.
    SELECT
        hadm_id
    FROM
        ranked_admissions
    WHERE
        admission_rank = 1
        AND age_at_admission BETWEEN 74 AND 84
),
total_icu_los_per_admission AS (
    -- Step 4: For each admission in the cohort, sum the ICU LOS from all associated ICU stays.
    SELECT
        f.hadm_id,
        SUM(i.los) AS total_icu_los_days
    FROM
        first_cabg_admissions_in_age_range AS f
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS i ON f.hadm_id = i.hadm_id
    GROUP BY
        f.hadm_id
)
-- Step 5: Calculate the average of the total ICU LOS values for the final cohort.
SELECT
    AVG(total_icu_los_days) AS mean_icu_los_days
FROM
    total_icu_los_per_admission;