WITH RelevantAdmissions AS (
    -- Step 1: Filter admissions for men aged 37-47
    SELECT
        ad.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 37 AND 47
),
RelevantProcedures AS (
    -- Step 2: Identify procedure codes related to catheter ablation or cardioversion
    SELECT
        pr.subject_id,
        pr.hadm_id,
        pr.icd_code
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
        ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
    WHERE
        LOWER(dp.long_title) LIKE '%catheter ablation%'
        OR LOWER(dp.long_title) LIKE '%cardioversion%'
),
AdmissionProcedureCounts AS (
    -- Step 3: Count distinct relevant procedures per admission,
    -- including those with zero procedures
    SELECT
        ra.hadm_id,
        -- Use COALESCE to ensure admissions with no relevant procedures count as 0
        COALESCE(COUNT(DISTINCT rp.icd_code), 0) AS distinct_procedure_count
    FROM
        RelevantAdmissions ra
    LEFT JOIN
        RelevantProcedures rp
        ON ra.subject_id = rp.subject_id AND ra.hadm_id = rp.hadm_id
    GROUP BY
        ra.hadm_id
)
-- Step 4: Calculate the standard deviation of distinct procedure counts
SELECT
    STDDEV(apc.distinct_procedure_count) AS stddev_distinct_procedures
FROM
    AdmissionProcedureCounts apc;