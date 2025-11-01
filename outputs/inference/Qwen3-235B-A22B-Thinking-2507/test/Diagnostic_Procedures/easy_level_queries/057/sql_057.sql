WITH filtered_procedures AS (
    SELECT 
        p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON pi.icd_code = d.icd_code 
        AND pi.icd_version = d.icd_version
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON pi.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        d.long_title ILIKE '%diagnostic%' 
        AND d.long_title ILIKE '%cardiac catheterization%'
        AND p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 64 AND 74
),
patient_counts AS (
    SELECT 
        subject_id,
        COUNT(*) AS procedure_count
    FROM filtered_procedures
    GROUP BY subject_id
)
SELECT 
    MIN(procedure_count) AS min_procedures_per_patient
FROM patient_counts;