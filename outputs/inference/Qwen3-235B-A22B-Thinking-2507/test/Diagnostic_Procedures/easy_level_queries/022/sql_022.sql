WITH target_admissions AS (
    SELECT 
        a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 82 AND 92
),
target_procedures AS (
    SELECT 
        hadm_id,
        icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE 
        (icd_version = 9 AND icd_code LIKE '37.7%') OR
        (icd_version = 9 AND icd_code LIKE '37.8%') OR
        (icd_version = 10 AND icd_code LIKE '02H0%') OR
        (icd_version = 10 AND icd_code LIKE '02H4%')
),
procedure_counts AS (
    SELECT 
        ta.hadm_id,
        COUNT(DISTINCT tp.icd_code) AS procedure_count
    FROM target_admissions ta
    INNER JOIN target_procedures tp
        ON ta.hadm_id = tp.hadm_id
    GROUP BY ta.hadm_id
)
SELECT MIN(procedure_count) AS min_procedures
FROM procedure_counts;