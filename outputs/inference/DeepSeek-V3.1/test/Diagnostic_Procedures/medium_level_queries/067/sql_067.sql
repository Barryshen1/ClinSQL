WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        pat.anchor_age,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hosp_los,
        MAX(CASE WHEN diag.seq_num = 1 THEN 1 ELSE 0 END) AS is_primary_acs,
        MAX(icu.los) AS icu_los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 39 AND 49
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
        AND diag.icd_version = 10
        AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code = 'I24.1')
    GROUP BY adm.subject_id, adm.hadm_id, pat.anchor_age, hosp_los
),
ultrasound_counts AS (
    SELECT 
        c.hadm_id,
        c.is_primary_acs,
        CASE 
            WHEN c.icu_los BETWEEN 1 AND 4 THEN '1-4'
            WHEN c.icu_los BETWEEN 5 AND 7 THEN '5-7'
            ELSE 'Other' 
        END AS icu_stay_group,
        COUNT(DISTINCT proc.procedure_id) AS ultrasound_count
    FROM cohort c
    LEFT JOIN (
        -- ICD-10 procedures starting with 'B' (Imaging)
        SELECT hadm_id, CAST(CONCAT(icd_code, icd_version) AS STRING) AS procedure_id
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
        WHERE icd_version = 10 AND icd_code LIKE 'B%'
        UNION ALL
        -- HCPCS codes for echo/ultrasound
        SELECT hadm_id, CAST(CONCAT(hcpcs_cd, 'HCPCS') AS STRING) AS procedure_id
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
        WHERE hcpcs_cd LIKE '93%' 
          AND (LOWER(short_description) LIKE '%echo%' OR LOWER(short_description) LIKE '%ultrasound%')
    ) proc
        ON c.hadm_id = proc.hadm_id
    WHERE c.icu_los BETWEEN 1 AND 7  -- Only include admissions with ICU stay in 1-7 days
    GROUP BY c.hadm_id, c.is_primary_acs, icu_stay_group
)
SELECT 
    is_primary_acs,
    icu_stay_group,
    APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(75)] AS p75
FROM ultrasound_counts
GROUP BY is_primary_acs, icu_stay_group
ORDER BY is_primary_acs, icu_stay_group;