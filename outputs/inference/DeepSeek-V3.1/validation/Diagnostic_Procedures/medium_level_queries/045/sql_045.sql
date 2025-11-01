WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id,
        CASE 
            WHEN icu.stay_id IS NOT NULL THEN 'ICU'
            ELSE 'no ICU'
        END AS icu_status,
        CASE 
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
            ELSE 'other'
        END AS los_group,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 78 AND 88
        AND d.long_title LIKE '%Deep vein thrombosis%'
        AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 8
    GROUP BY adm.subject_id, adm.hadm_id, icu_status, los_group, los_days
),

lab_diagnostics AS (
    SELECT 
        hadm_id,
        COUNT(*) AS count_diagnostics
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid = 51179  -- D-dimer
    GROUP BY hadm_id
),

proc_diagnostics AS (
    SELECT 
        hadm_id,
        COUNT(*) AS count_diagnostics
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE icd_code IN ('4A03X4Z', '4A03X5Z', 'B04ZZZ')
    GROUP BY hadm_id

    UNION ALL

    SELECT 
        hadm_id,
        COUNT(*) AS count_diagnostics
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE hcpcs_cd IN ('93965', '93970', '93971')
    GROUP BY hadm_id
),

combined_diagnostics AS (
    SELECT 
        hadm_id,
        SUM(count_diagnostics) AS total_diagnostics
    FROM (
        SELECT * FROM lab_diagnostics
        UNION ALL
        SELECT * FROM proc_diagnostics
    )
    GROUP BY hadm_id
)

SELECT 
    c.icu_status,
    c.los_group,
    COUNT(c.hadm_id) AS num_admissions,
    COALESCE(AVG(cd.total_diagnostics), 0) AS mean_diagnostics_per_admission
FROM cohort c
LEFT JOIN combined_diagnostics cd
    ON c.hadm_id = cd.hadm_id
WHERE c.los_group IN ('1-4', '5-8')
GROUP BY c.icu_status, c.los_group
ORDER BY c.icu_status, c.los_group;