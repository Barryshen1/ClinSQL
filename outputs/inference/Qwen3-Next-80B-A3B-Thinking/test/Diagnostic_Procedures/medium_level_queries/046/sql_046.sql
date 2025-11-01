WITH tia_patients AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON p.subject_id = di.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 50 AND 60
        AND (d.long_title LIKE '%TIA%' OR d.long_title LIKE '%Transient Ischemic Attack%')
),
admissions_los AS (
    SELECT 
        a.hadm_id,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN tia_patients tp ON a.hadm_id = tp.hadm_id
),
ct_mri_counts AS (
    SELECT hadm_id, COUNT(*) AS ct_mri_count
    FROM (
        -- hcpcsevents
        SELECT h.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
        WHERE h.short_description LIKE '%CT%' OR h.short_description LIKE '%MRI%'
        
        UNION ALL
        
        -- procedures_icd
        SELECT p.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
            ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
        WHERE d.long_title LIKE '%CT%' OR d.long_title LIKE '%MRI%' 
            OR d.long_title LIKE '%Computed Tomography%' 
            OR d.long_title LIKE '%Magnetic Resonance Imaging%'
        
        UNION ALL
        
        -- chartevents in ICU module
        SELECT c.hadm_id
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
        JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
            ON c.itemid = d.itemid
        WHERE d.label LIKE '%CT%' OR d.label LIKE '%MRI%'
    ) AS combined
    GROUP BY hadm_id
)
SELECT 
    CASE 
        WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    COUNT(DISTINCT a.hadm_id) AS patient_count,
    AVG(COALESCE(cm.ct_mri_count, 0)) AS mean_procedures
FROM admissions_los a
LEFT JOIN ct_mri_counts cm ON a.hadm_id = cm.hadm_id
WHERE los_days BETWEEN 1 AND 7
GROUP BY los_group;