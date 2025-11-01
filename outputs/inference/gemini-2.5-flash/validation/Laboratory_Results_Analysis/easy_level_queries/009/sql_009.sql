WITH FemaleACSAdmissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
        ON adm.subject_id = dicd.subject_id
        AND adm.hadm_id = dicd.hadm_id
    WHERE
        pat.gender = 'F'
        AND (
            -- Filter for Acute Coronary Syndrome (ACS) ICD-10 codes
            (dicd.icd_version = 10 AND (
                dicd.icd_code = 'I200' OR                        -- Unstable angina (I20.0)
                STARTS_WITH(dicd.icd_code, 'I21') OR             -- Acute myocardial infarction (I21.x)
                STARTS_WITH(dicd.icd_code, 'I22') OR             -- Subsequent myocardial infarction (I22.x)
                STARTS_WITH(dicd.icd_code, 'I24')                -- Other acute ischemic heart disease (I24.x)
            ))
            OR
            -- Filter for Acute Coronary Syndrome (ACS) ICD-9 codes
            (dicd.icd_version = 9 AND (
                STARTS_WITH(dicd.icd_code, '410') OR
                dicd.icd_code = '4111' OR                        -- Intermediate coronary syndrome/Unstable angina (411.1)
                dicd.icd_code = '4118'                           -- Other specified forms of acute ischemic heart disease (411.8)
            ))
        )
),
NadirTroponinPerAdmission AS (
    SELECT
        acs.hadm_id,
        MIN(le.valuenum) AS nadir_troponin_value
    FROM
        FemaleACSAdmissions acs
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON acs.subject_id = le.subject_id
        AND acs.hadm_id = le.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE
        regexp_contains(dli.label, r'(?i)troponin') -- Case-insensitive search for 'troponin' in lab item label
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.charttime BETWEEN acs.admittime AND acs.dischtime -- Lab event happened during admission
    GROUP BY
        acs.hadm_id
)
SELECT
    APPROX_QUANTILES(nadir_troponin_value, 100)[OFFSET(25)] AS percentile_25_nadir_troponin
FROM NadirTroponinPerAdmission;