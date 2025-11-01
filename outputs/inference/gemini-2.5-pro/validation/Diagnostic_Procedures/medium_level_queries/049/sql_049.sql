WITH
-- Step 1: Identify admissions for male patients aged 87-97 with a relevant length of stay.
base_admissions AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 87 AND 97
        AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Step 2: Flag admissions with sepsis and/or septic shock diagnoses using ICD codes.
diagnosis_flags AS (
    SELECT
        hadm_id,
        -- Flag for any sepsis-related diagnosis
        MAX(CASE
            WHEN icd_version = 9 AND (icd_code LIKE '038%' OR icd_code = '99591') THEN 1
            WHEN icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%') THEN 1
            ELSE 0
        END) AS has_sepsis,
        -- Flag for any septic shock diagnosis
        MAX(CASE
            WHEN icd_version = 9 AND icd_code = '78552' THEN 1
            WHEN icd_version = 10 AND icd_code = 'R6521' THEN 1
            ELSE 0
        END) AS has_septic_shock
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
        hadm_id
),

-- Step 3: Filter for the final cohort: male patients 87-97 with sepsis but NO septic shock.
cohort_admissions AS (
    SELECT
        b.hadm_id,
        b.los
    FROM
        base_admissions AS b
    INNER JOIN
        diagnosis_flags AS d
        ON b.hadm_id = d.hadm_id
    WHERE
        d.has_sepsis = 1
        AND d.has_septic_shock = 0
),

-- Step 4: Count the number of procedures for each admission in the final cohort.
proc_counts AS (
    SELECT
        c.hadm_id,
        c.los,
        COUNT(p.icd_code) AS num_procedures
    FROM
        cohort_admissions AS c
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
        ON c.hadm_id = p.hadm_id
    GROUP BY
        c.hadm_id, c.los
)

-- Step 5: Final aggregation to calculate the mean number of procedures for the two length-of-stay groups.
SELECT
    CASE
        WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
    END AS admission_length_group,
    AVG(num_procedures) AS mean_diagnostic_procedures
FROM
    proc_counts
GROUP BY
    admission_length_group
ORDER BY
    admission_length_group;