WITH hf_patients AS (
    SELECT DISTINCT p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        ON p.subject_id = di.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE p.gender = 'F'
        AND p.anchor_age = 74
        AND (dd.icd_code LIKE '428%' OR dd.icd_code LIKE 'I50%')
),
admissions_with_type AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admission_type,
        CASE 
            WHEN a.admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED/Urgent'
            WHEN a.admission_type = 'ELECTIVE' THEN 'Elective'
            ELSE 'Other'
        END AS admission_category
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN hf_patients hp ON a.subject_id = hp.subject_id
),
icu_stays AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.los,
        CASE 
            WHEN i.los BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN i.los BETWEEN 5 AND 7 THEN '5-7 days'
        END AS los_group
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN hf_patients hp ON i.subject_id = hp.subject_id
    WHERE i.los BETWEEN 1 AND 7
),
icd_procedures AS (
    SELECT 
        pi.subject_id,
        pi.hadm_id,
        dp.long_title AS procedure_name
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp 
        ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
    WHERE LOWER(dp.long_title) LIKE '%imaging%'
        OR LOWER(dp.long_title) LIKE '%x-ray%'
        OR LOWER(dp.long_title) LIKE '%ct%'
        OR LOWER(dp.long_title) LIKE '%mri%'
        OR LOWER(dp.long_title) LIKE '%ecg%'
        OR LOWER(dp.long_title) LIKE '%electrocardiogram%'
        OR LOWER(dp.long_title) LIKE '%eeg%'
        OR LOWER(dp.long_title) LIKE '%electroencephalogram%'
        OR LOWER(dp.long_title) LIKE '%pft%'
        OR LOWER(dp.long_title) LIKE '%pulmonary function%'
),
hcpcs_procedures AS (
    SELECT 
        he.subject_id,
        he.hadm_id,
        dh.long_description AS procedure_name
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh 
        ON he.hcpcs_cd = dh.code
    WHERE LOWER(dh.long_description) LIKE '%imaging%'
        OR LOWER(dh.long_description) LIKE '%x-ray%'
        OR LOWER(dh.long_description) LIKE '%ct%'
        OR LOWER(dh.long_description) LIKE '%mri%'
        OR LOWER(dh.long_description) LIKE '%ecg%'
        OR LOWER(dh.long_description) LIKE '%electrocardiogram%'
        OR LOWER(dh.long_description) LIKE '%eeg%'
        OR LOWER(dh.long_description) LIKE '%electroencephalogram%'
        OR LOWER(dh.long_description) LIKE '%pft%'
        OR LOWER(dh.long_description) LIKE '%pulmonary function%'
),
all_procedures AS (
    SELECT subject_id, hadm_id, procedure_name FROM icd_procedures
    UNION DISTINCT
    SELECT subject_id, hadm_id, procedure_name FROM hcpcs_procedures
),
procedures_per_stay AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.los_group,
        a.admission_category,
        COUNT(DISTINCT ap.procedure_name) AS num_procedures
    FROM icu_stays i
    INNER JOIN admissions_with_type a 
        ON i.hadm_id = a.hadm_id
    LEFT JOIN all_procedures ap 
        ON i.hadm_id = ap.hadm_id
    GROUP BY i.subject_id, i.hadm_id, i.stay_id, i.los_group, a.admission_category
)
SELECT 
    admission_category,
    los_group,
    AVG(num_procedures) AS mean_procedures_per_admission
FROM procedures_per_stay
WHERE admission_category IN ('ED/Urgent', 'Elective')
    AND los_group IS NOT NULL
GROUP BY admission_category, los_group
ORDER BY admission_category, los_group;