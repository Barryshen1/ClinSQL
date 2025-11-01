WITH proc_counts AS (
    SELECT 
        a.hadm_id,
        COUNT(DISTINCT p.icd_code) AS num_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON a.subject_id = pt.subject_id
    WHERE 
        pt.gender = 'M'
        AND pt.anchor_age BETWEEN 37 AND 47
        AND p.icd_version = 10
        AND (p.icd_code LIKE '0258%' OR p.icd_code = '5A2204Z')
    GROUP BY a.hadm_id
)
SELECT 
    STDDEV(num_procedures) AS sd_procedures
FROM proc_counts;