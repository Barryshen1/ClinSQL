WITH patient_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        TIMESTAMP_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
),
filtered_admissions AS (
    SELECT *
    FROM patient_admissions
    WHERE age_at_admission BETWEEN 82 AND 92
),
pacemaker_procedures AS (
    SELECT 
        pip.subject_id,
        pip.hadm_id,
        pip.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pip
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
        ON pip.icd_code = dip.icd_code AND pip.icd_version = dip.icd_version
    WHERE dip.long_title LIKE '%pacemaker%' OR dip.long_title LIKE '%ICD%'
),
procedures_per_hadm AS (
    SELECT 
        fa.hadm_id,
        COUNT(DISTINCT pp.icd_code) AS distinct_procedure_count
    FROM filtered_admissions fa
    LEFT JOIN pacemaker_procedures pp 
        ON fa.subject_id = pp.subject_id AND fa.hadm_id = pp.hadm_id
    GROUP BY fa.hadm_id
)
SELECT MIN(distinct_procedure_count) AS min_distinct_procedures
FROM procedures_per_hadm;