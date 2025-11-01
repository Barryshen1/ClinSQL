WITH eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
      AND anchor_age BETWEEN 40 AND 50
),
mechanical_procedures AS (
    SELECT 
        p.subject_id,
        p.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE 
        LOWER(d.long_title) LIKE '%mechanical%' 
        OR LOWER(d.long_title) LIKE '%circulatory support%'
        OR LOWER(d.long_title) LIKE '%ecmo%'
        OR LOWER(d.long_title) LIKE '%vad%'
        OR LOWER(d.long_title) LIKE '%ventricular assist%'
),
patient_procedure_counts AS (
    SELECT 
        ep.subject_id,
        COUNT(DISTINCT mp.icd_code) AS distinct_procedures
    FROM eligible_patients ep
    LEFT JOIN mechanical_procedures mp
        ON ep.subject_id = mp.subject_id
    GROUP BY ep.subject_id
)
SELECT 
    MIN(distinct_procedures) AS min_distinct_procedures
FROM patient_procedure_counts;