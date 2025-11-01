WITH target_admissions AS (
    SELECT DISTINCT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 86 AND 96
),
proc_counts AS (
    SELECT 
        ta.hadm_id,
        COUNT(DISTINCT picd.icd_code) AS distinct_proc_count
    FROM target_admissions ta
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
        ON ta.hadm_id = picd.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON picd.icd_code = dicd.icd_code 
        AND picd.icd_version = dicd.icd_version
    WHERE 
        -- Mechanical circulatory support ICD-10 codes
        (dicd.icd_code LIKE '5A021%'   -- Insertion of intra-aortic balloon pump
        OR dicd.icd_code LIKE '5A022%' -- Insertion of other temporary cardiac assist device
        OR dicd.icd_code LIKE '02HA0%' -- Insertion of percutaneous external heart assist system
        OR dicd.icd_code LIKE '5A1%'   -- Other circulatory support
        OR dicd.icd_code LIKE '02H%'   -- Other heart assist systems
        )
        OR dicd.long_title LIKE '%mechanical circulatory support%'
        OR dicd.long_title LIKE '%heart assist%'
        OR dicd.long_title LIKE '%intra-aortic balloon%'
    GROUP BY ta.hadm_id
)
SELECT 
    DISTINCT
    PERCENTILE_CONT(distinct_proc_count, 0.25) OVER() AS q1,
    PERCENTILE_CONT(distinct_proc_count, 0.75) OVER() AS q3,
    PERCENTILE_CONT(distinct_proc_count, 0.75) OVER() - PERCENTILE_CONT(distinct_proc_count, 0.25) OVER() AS iqr
FROM proc_counts;