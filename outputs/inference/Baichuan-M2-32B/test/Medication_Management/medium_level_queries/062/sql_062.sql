WITH eligible_patients AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        p.anchor_age AS age_at_index
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 50 AND 60
),
diagnoses AS (
    SELECT
        d.subject_id,
        d.hadm_id,
        d.icd_code,
        diag.long_title
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
        ON d.icd_code = diag.icd_code
        AND d.icd_version = diag.icd_version
    WHERE diag.long_title LIKE '%diabetes%' OR diag.long_title LIKE '%heart failure%'
),
cohort_admissions AS (
    SELECT
        ep.subject_id,
        ep.hadm_id,
        ep.admittime,
        ep.dischtime
    FROM eligible_patients ep
    WHERE EXISTS (
        SELECT 1
        FROM diagnoses d1
        WHERE d1.subject_id = ep.subject_id
            AND d1.hadm_id = ep.hadm_id
            AND d1.long_title LIKE '%diabetes%'
    )
    AND EXISTS (
        SELECT 1
        FROM diagnoses d2
        WHERE d2.subject_id = ep.subject_id
            AND d2.hadm_id = ep.hadm_id
            AND d2.long_title LIKE '%heart failure%'
    )
),
glp1_prescriptions AS (
    SELECT
        p.subject_id,
        p.hadm_id,
        p.starttime,
        p.drug,
        p.route,
        ROW_NUMBER() OVER (
            PARTITION BY p.subject_id, p.hadm_id, p.drug
            ORDER BY p.starttime
        ) AS rx_seq
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE 
        (p.drug LIKE '%semaglutide%' OR p.drug LIKE '%tirzepatide%' OR p.drug LIKE '%GLP-1%')
        AND p.route IN ('Subcutaneous', 'Intravenous')
),
initiations AS (
    SELECT
        gp.subject_id,
        gp.hadm_id,
        gp.starttime,
        CASE 
            WHEN gp.rx_seq = 1 THEN 1 
            ELSE 0 
        END AS is_initiation
    FROM glp1_prescriptions gp
),
time_windows AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) AS first_72h_end,
        DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AS final_72h_start
    FROM cohort_admissions c
),
admission_glps AS (
    SELECT
        tw.subject_id,
        tw.hadm_id,
        SUM(CASE 
            WHEN i.starttime BETWEEN tw.admittime AND tw.first_72h_end 
            THEN i.is_initiation 
            ELSE 0 
        END) AS first_72h_initiations,
        SUM(CASE 
            WHEN i.starttime BETWEEN 
                GREATEST(tw.admittime, tw.final_72h_start) AND tw.dischtime 
            THEN i.is_initiation 
            ELSE 0 
        END) AS final_72h_initiations
    FROM time_windows tw
    LEFT JOIN initiations i
        ON tw.subject_id = i.subject_id
        AND tw.hadm_id = i.hadm_id
    GROUP BY tw.subject_id, tw.hadm_id
)
SELECT
    COUNT(DISTINCT hadm_id) AS total_admissions,
    SUM(first_72h_initiations) AS total_first_72h_initiations,
    SUM(final_72h_initiations) AS total_final_72h_initiations,
    SUM(final_72h_initiations) - SUM(first_72h_initiations) AS absolute_change,
    CASE 
        WHEN SUM(first_72h_initiations) > 0 
        THEN (SUM(final_72h_initiations) - SUM(first_72h_initiations)) / SUM(first_72h_initiations) 
        ELSE NULL 
    END AS relative_change
FROM admission_glps;