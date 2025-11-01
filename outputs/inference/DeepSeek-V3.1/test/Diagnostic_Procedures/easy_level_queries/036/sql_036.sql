WITH valve_procedures AS (
    SELECT 
        p.subject_id,
        COUNT(DISTINCT proc.icd_code) AS distinct_valve_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON adm.subject_id = proc.subject_id AND adm.hadm_id = proc.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 42 AND 52
        AND dicd.long_title LIKE '%valve%'
    GROUP BY p.subject_id
)
SELECT 
    AVG(distinct_valve_procedures) AS avg_distinct_valve_procedures_per_patient
FROM valve_procedures;