WITH hf_admissions AS (
    -- First, find all hospital admissions (hadm_id) for a diagnosis of heart failure.
    SELECT DISTINCT dia.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
        ON dia.icd_code = d.icd_code
        AND dia.icd_version = d.icd_version
    WHERE
        LOWER(d.long_title) LIKE '%heart failure%'
),

cohort_admissions AS (
    -- Next, define the specific cohort of admissions based on patient demographics and admission characteristics.
    SELECT
        adm.hadm_id,
        CASE
            WHEN adm.admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED/Urgent'
            WHEN adm.admission_type = 'ELECTIVE' THEN 'Elective'
            ELSE NULL
        END AS admission_group,
        CASE
            -- Calculate length of stay in days, rounding up partial days.
            WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 5 AND 7 THEN '5-7 days'
            ELSE NULL
        END AS los_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    -- Ensure the admission is for a heart failure diagnosis.
    INNER JOIN hf_admissions AS hf
        ON adm.hadm_id = hf.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age = 74
        AND adm.dischtime IS NOT NULL -- Exclude admissions that are ongoing or have no discharge time
),

diagnostic_counts AS (
    -- Count the number of relevant non-invasive diagnostics for each admission using HCPCS codes.
    SELECT
        hadm_id,
        COUNT(hcpcs_cd) AS num_diagnostics
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE
        -- HCPCS codes for Radiology/Imaging (7xxxx)
        (hcpcs_cd BETWEEN '70010' AND '79999')
        -- HCPCS codes for Cardiovascular/ECG (93xxx)
        OR (hcpcs_cd BETWEEN '93000' AND '93799')
        -- HCPCS codes for Pulmonary/PFT (94xxx)
        OR (hcpcs_cd BETWEEN '94000' AND '94799')
        -- HCPCS codes for Neurology/EEG (95xxx)
        OR (hcpcs_cd BETWEEN '95800' AND '95999')
    GROUP BY
        hadm_id
)

-- Final step: Join the cohort with the diagnostic counts and calculate the average per stratum.
SELECT
    ca.admission_group,
    ca.los_group,
    AVG(COALESCE(dc.num_diagnostics, 0)) AS mean_diagnostics_per_admission
FROM cohort_admissions AS ca
LEFT JOIN diagnostic_counts AS dc
    ON ca.hadm_id = dc.hadm_id
WHERE
    -- Filter out admissions that do not fall into our defined groups.
    ca.admission_group IS NOT NULL
    AND ca.los_group IS NOT NULL
GROUP BY
    ca.admission_group,
    ca.los_group
ORDER BY
    ca.admission_group,
    ca.los_group;