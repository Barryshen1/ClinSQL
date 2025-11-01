WITH acs_admissions_status AS (
    -- First, identify admissions for patients aged 77-87 with any ACS diagnosis
    -- and determine if they have a primary or secondary ACS diagnosis.
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Detect if there's a primary ACS diagnosis (seq_num = 1)
        MAX(CASE
                WHEN diag.seq_num = 1
                AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code LIKE 'I24.1%' OR diag.icd_code LIKE 'I24.8%' OR diag.icd_code LIKE 'I24.9%')
                THEN 1
                ELSE 0
            END) AS has_primary_acs,
        -- Detect if there's a secondary ACS diagnosis (seq_num > 1)
        MAX(CASE
                WHEN diag.seq_num > 1
                AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code LIKE 'I24.1%' OR diag.icd_code LIKE 'I24.8%' OR diag.icd_code LIKE 'I24.9%')
                THEN 1
                ELSE 0
            END) AS has_secondary_acs
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE
        pat.anchor_age BETWEEN 77 AND 87
        AND adm.hospital_expire_flag IS NOT NULL -- Ensure valid admission/discharge records
        AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL -- Ensure LOS can be calculated
    GROUP BY
        adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
    HAVING
        -- Ensure that the admission actually has an ACS diagnosis to be considered an "ACS admission"
        has_primary_acs = 1 OR has_secondary_acs = 1
),
categorized_acs_admissions AS (
    -- Assign the final diagnosis type (Primary ACS takes precedence) and LOS category
    SELECT
        subject_id,
        hadm_id,
        los_days,
        CASE
            WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
            ELSE 'Other' -- Exclude other LOS categories in final analysis
        END AS los_category,
        CASE
            WHEN has_primary_acs = 1 THEN 'Primary ACS'
            WHEN has_primary_acs = 0 AND has_secondary_acs = 1 THEN 'Secondary ACS'
            ELSE 'Unknown' -- Should not be reached due to HAVING clause in previous CTE
        END AS acs_diagnosis_type
    FROM
        acs_admissions_status
    WHERE
        los_days BETWEEN 1 AND 8 -- Focus on 1-4 or 5-8 day stays as requested
),
radiography_ct_counts_per_admission AS (
    -- Count radiography/CT procedures for each relevant admission
    SELECT
        caa.subject_id,
        caa.hadm_id,
        caa.los_category,
        caa.acs_diagnosis_type,
        COUNT(DISTINCT
            CASE
                WHEN d_proc.long_title LIKE '%radiograph%'
                    OR d_proc.long_title LIKE '%X-ray%'
                    OR d_proc.long_title LIKE '%CT scan%'
                    OR d_proc.long_title LIKE '%computed tomography%'
                THEN proc.icd_code -- Count the specific ICD code for the procedure
                ELSE NULL
            END
        ) AS radiography_ct_count
    FROM
        categorized_acs_admissions caa
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON caa.subject_id = proc.subject_id AND caa.hadm_id = proc.hadm_id
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
        ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    GROUP BY
        caa.subject_id, caa.hadm_id, caa.los_category, caa.acs_diagnosis_type
)
-- Final aggregation to get mean, min, max counts
SELECT
    rpc.los_category,
    rpc.acs_diagnosis_type,
    COUNT(DISTINCT rpc.hadm_id) AS num_admissions,
    IFNULL(ROUND(AVG(rpc.radiography_ct_count), 2), 0) AS mean_radiography_ct_count,
    IFNULL(MIN(rpc.radiography_ct_count), 0) AS min_radiography_ct_count,
    IFNULL(MAX(rpc.radiography_ct_count), 0) AS max_radiography_ct_count
FROM
    radiography_ct_counts_per_admission rpc
GROUP BY
    rpc.los_category,
    rpc.acs_diagnosis_type
ORDER BY
    rpc.los_category,
    rpc.acs_diagnosis_type;