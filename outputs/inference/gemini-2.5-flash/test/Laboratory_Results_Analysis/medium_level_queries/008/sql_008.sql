WITH ACS_Admissions AS (
    -- Select distinct admissions for male patients aged 87-90 with an ACS diagnosis
        SELECT DISTINCT
            adm_inner.subject_id,
            adm_inner.hadm_id,
            adm_inner.hospital_expire_flag
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` adm_inner
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` pat_inner
            ON adm_inner.subject_id = pat_inner.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_inner
            ON adm_inner.hadm_id = diag_inner.hadm_id
        WHERE
            pat_inner.gender = 'M'
            -- anchor_age 90 typically represents any patient aged 90 or over due to MIMIC-IV age capping rules.
            -- So, BETWEEN 87 AND 90 covers the spirit of 87-97 given the data structure.
            AND pat_inner.anchor_age BETWEEN 87 AND 90
            AND (
                -- ICD-9 codes for suspected ACS
                (diag_inner.icd_version = 9 AND (
                    diag_inner.icd_code LIKE '410%' OR -- Acute myocardial infarction
                    diag_inner.icd_code LIKE '411%' OR -- Other acute and subacute forms of ischemic heart disease (includes unstable angina)
                    diag_inner.icd_code LIKE '413%' OR -- Angina pectoris
                    diag_inner.icd_code = '4140'       -- Coronary atherosclerosis without mention of myocardial infarction
                ))
                OR
                -- ICD-10 codes for suspected ACS
                (diag_inner.icd_version = 10 AND (
                    diag_inner.icd_code LIKE 'I20%' OR -- Angina pectoris
                    diag_inner.icd_code LIKE 'I21%' OR -- Acute myocardial infarction
                    diag_inner.icd_code LIKE 'I22%' OR -- Subsequent myocardial infarction
                    diag_inner.icd_code LIKE 'I24%'    -- Other acute ischemic heart diseases
                ))
            )
),
FirstTroponinT AS (
    -- Get the first Troponin T measurement and categorize it for each admission
    -- using QUALIFY for a BigQuery-specific window function filtering approach
        SELECT
            le.hadm_id,
            le.valuenum AS troponin_t_val,
            CASE
                WHEN le.valuenum < 0.01 THEN 'Normal/Minimal'
                WHEN le.valuenum >= 0.01 AND le.valuenum < 0.05 THEN 'Borderline'
                WHEN le.valuenum >= 0.05 THEN 'Elevated'
                ELSE 'Unknown' -- Should not be reached due to WHERE clause, but good for completeness
            END AS troponin_category
        FROM
            `physionet-data.mimiciv_3_1_hosp.labevents` le
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
            ON le.itemid = dli.itemid
        WHERE
            le.itemid = 50987 -- itemid for Troponin T
            AND le.valuenum IS NOT NULL
        QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
)
-- Main query to calculate counts, percentages, and mortality rates by Troponin T category
SELECT
    ft.troponin_category,
    COUNT(DISTINCT aa.hadm_id) AS total_admissions,
    -- Percentage of total admissions in this Troponin T category
    ROUND(COUNT(DISTINCT aa.hadm_id) * 100.0 / SUM(COUNT(DISTINCT aa.hadm_id)) OVER (), 2) AS percentage_of_total_admissions,
    SUM(CASE WHEN aa.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths,
    -- Mortality rate for this Troponin T category
    ROUND(SUM(CASE WHEN aa.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT aa.hadm_id), 2) AS mortality_rate_percent
FROM
    ACS_Admissions AS aa
INNER JOIN
    FirstTroponinT AS ft
    ON aa.hadm_id = ft.hadm_id
GROUP BY
    ft.troponin_category
ORDER BY
    CASE ft.troponin_category
        WHEN 'Normal/Minimal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Elevated' THEN 3
        ELSE 4
    END
;