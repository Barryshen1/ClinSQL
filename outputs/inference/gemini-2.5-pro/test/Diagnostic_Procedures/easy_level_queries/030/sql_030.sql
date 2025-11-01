WITH cohort_hadm AS (
    SELECT
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 84 AND 94
),

-- CTE to identify all echo procedures from the procedures_icd table
echo_procs AS (
    SELECT
        proc.hadm_id,
        proc.icd_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
            ON proc.icd_code = d_proc.icd_code
            AND proc.icd_version = d_proc.icd_version
    WHERE
        LOWER(d_proc.long_title) LIKE '%echocardiogram%'
        OR LOWER(d_proc.long_title) LIKE '%echocardiography%'
),

-- CTE to count the number of distinct echo procedures for each hospitalization in the cohort.
-- A LEFT JOIN ensures that hospitalizations with zero echo procedures are included with a count of 0.
counts_per_hadm AS (
    SELECT
        ch.hadm_id,
        COUNT(DISTINCT ep.icd_code) AS num_distinct_echo_procedures
    FROM
        cohort_hadm AS ch
    LEFT JOIN
        echo_procs AS ep
            ON ch.hadm_id = ep.hadm_id
    GROUP BY
        ch.hadm_id
)

-- Final step: calculate the 25th percentile of the counts across all relevant hospitalizations.
SELECT
    APPROX_QUANTILES(num_distinct_echo_procedures, 100)[OFFSET(25)] AS p25_distinct_echo_procedures
FROM
    counts_per_hadm;