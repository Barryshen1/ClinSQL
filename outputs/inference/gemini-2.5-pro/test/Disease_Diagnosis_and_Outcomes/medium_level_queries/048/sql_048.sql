WITH cohort_admissions AS (
    -- Step 1: Identify the cohort of male patients aged 68-78 at the time of admission
    -- Step 2: Calculate hospital LOS and create stratification groups
    SELECT
        a.hadm_id,
        a.hospital_expire_flag,
        CASE
            WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24.0 * 3600.0) < 8 THEN '< 8 days'
            ELSE '>= 8 days'
        END AS los_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'M'
        AND a.dischtime IS NOT NULL -- Ensure LOS can be calculated
        AND a.admittime IS NOT NULL
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 68 AND 78
),
diagnosis_flags AS (
    -- Step 3: For each admission in the cohort, create flags for CKD and Diabetes
    SELECT
        hadm_id,
        MAX(
            CASE
                WHEN (icd_version = 9 AND icd_code LIKE '585%')
                    OR (icd_version = 10 AND icd_code LIKE 'N18%')
                THEN 1
                ELSE 0
            END
        ) AS has_ckd,
        MAX(
            CASE
                WHEN (icd_version = 9 AND icd_code LIKE '250%')
                    OR (icd_version = 10 AND (
                        icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%'
                        OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'
                        )
                    )
                THEN 1
                ELSE 0
            END
        ) AS has_diabetes
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        hadm_id IN (SELECT hadm_id FROM cohort_admissions) -- Filter for efficiency
    GROUP BY
        hadm_id
)
-- Step 4: Join cohort with diagnoses and calculate final metrics
SELECT
    c.los_group,
    COUNT(c.hadm_id) AS total_admissions,
    -- Use AVG on binary flags (0/1) to get the proportion, then multiply by 100 for percentage
    ROUND(AVG(c.hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent,
    ROUND(AVG(COALESCE(d.has_ckd, 0)) * 100, 2) AS ckd_prevalence_percent,
    ROUND(AVG(COALESCE(d.has_diabetes, 0)) * 100, 2) AS diabetes_prevalence_percent
FROM
    cohort_admissions AS c
LEFT JOIN
    diagnosis_flags AS d
    ON c.hadm_id = d.hadm_id
GROUP BY
    c.los_group
ORDER BY
    c.los_group;