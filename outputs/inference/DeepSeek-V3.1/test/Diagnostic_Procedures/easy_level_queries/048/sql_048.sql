WITH demo_admissions AS (
    SELECT 
        adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 52 AND 62
),

valve_procedures AS (
    SELECT 
        proc.hadm_id,
        proc.icd_code,
        proc.icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code 
        AND proc.icd_version = dicd.icd_version
    WHERE 
        LOWER(dicd.long_title) LIKE '%valve%'
        AND (LOWER(dicd.long_title) LIKE '%repair%' 
             OR LOWER(dicd.long_title) LIKE '%replacement%')
),

procedure_counts AS (
    SELECT 
        da.hadm_id,
        COUNT(DISTINCT vp.icd_code) AS num_valve_procedures
    FROM demo_admissions da
    LEFT JOIN valve_procedures vp
        ON da.hadm_id = vp.hadm_id
    GROUP BY da.hadm_id
)

SELECT 
    PERCENTILE_CONT(num_valve_procedures, 0.25) OVER() AS q25,
    PERCENTILE_CONT(num_valve_procedures, 0.75) OVER() AS q75,
    PERCENTILE_CONT(num_valve_procedures, 0.75) OVER() - 
        PERCENTILE_CONT(num_valve_procedures, 0.25) OVER() AS iqr
FROM procedure_counts
LIMIT 1;