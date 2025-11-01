WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE 
            WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu`.icustays icu WHERE icu.hadm_id = adm.hadm_id) 
            THEN 'ICU' 
            ELSE 'no ICU' 
        END AS icu_flag,
        CASE 
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
            ELSE 'Other' 
        END AS los_group
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 57 AND 67
        AND adm.hadm_id IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd 
            WHERE icd_code IN ('R65.21', '785.52')
        )
),
us_procedures AS (
    -- ICD procedures for ultrasounds
    SELECT hadm_id, chartdate, icd_code
    FROM `physionet-data.mimiciv_3_1_hosp`.procedures_icd
    WHERE icd_code IN (
        SELECT icd_code 
        FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures 
        WHERE long_title LIKE '%ultrasound%' OR long_title LIKE '%echocardiogram%'
    )
    UNION ALL
    -- HCPCS procedures for ultrasounds
    SELECT hadm_id, chartdate, hcpcs_cd AS icd_code
    FROM `physionet-data.mimiciv_3_1_hosp`.hcpcsevents
    WHERE hcpcs_cd IN (
        SELECT code 
        FROM `physionet-data.mimiciv_3_1_hosp`.d_hcpcs 
        WHERE long_description LIKE '%ultrasound%' OR long_description LIKE '%echocardiogram%'
    )
),
us_counts AS (
    SELECT 
        c.hadm_id,
        c.icu_flag,
        c.los_group,
        COUNT(us.icd_code) AS us_count  -- Count each ultrasound procedure
    FROM cohort c
    LEFT JOIN us_procedures us
        ON c.hadm_id = us.hadm_id
    GROUP BY c.hadm_id, c.icu_flag, c.los_group
)

SELECT 
    icu_flag,
    los_group,
    APPROX_QUANTILES(us_count, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(us_count, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(us_count, 100)[OFFSET(75)] AS p75,
    COUNT(*) AS n_admissions
FROM us_counts
WHERE los_group IN ('1-3', '4-7')
GROUP BY icu_flag, los_group
ORDER BY icu_flag, los_group;