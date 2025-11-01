WITH FilteredPatients AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 51 AND 61
),
-- CTE to find the first hospital admission for these filtered patients
FirstHospitalAdmission AS (
    SELECT
        ad.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        FilteredPatients fp
    ON
        ad.subject_id = fp.subject_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ad.subject_id ORDER BY ad.admittime ASC) = 1
),
-- CTE to identify these first admissions that have a pneumonia diagnosis
PneumoniaFirstAdmissions AS (
    SELECT DISTINCT
        fha.subject_id,
        fha.hadm_id
    FROM
        FirstHospitalAdmission fha
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON
        fha.subject_id = di.subject_id
        AND fha.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND (
            STARTS_WITH(di.icd_code, '480') OR -- Viral pneumonia
            STARTS_WITH(di.icd_code, '481') OR -- Pneumococcal pneumonia
            STARTS_WITH(di.icd_code, '482') OR -- Other bacterial pneumonia
            STARTS_WITH(di.icd_code, '483') OR -- Pneumonia due to other specified organism
            STARTS_WITH(di.icd_code, '484') OR -- Pneumonia in infectious diseases classified elsewhere
            STARTS_WITH(di.icd_code, '485') OR -- Bronchopneumonia, organism unspecified
            STARTS_WITH(di.icd_code, '486')    -- Pneumonia, organism unspecified
        ))
        OR
        (di.icd_version = 10 AND (
            STARTS_WITH(di.icd_code, 'J12') OR -- Viral pneumonia, not elsewhere classified
            STARTS_WITH(di.icd_code, 'J13') OR -- Pneumonia due to Streptococcus pneumoniae
            STARTS_WITH(di.icd_code, 'J14') OR -- Pneumonia due to Haemophilus influenzae
            STARTS_WITH(di.icd_code, 'J15') OR -- Bacterial pneumonia, not elsewhere classified
            STARTS_WITH(di.icd_code, 'J16') OR -- Pneumonia due to other infectious organisms, not elsewhere classified
            STARTS_WITH(di.icd_code, 'J17') OR -- Pneumonia in diseases classified elsewhere
            STARTS_WITH(di.icd_code, 'J18')    -- Pneumonia, unspecified organism
        ))
),
-- CTE to find the first ICU stay within these pneumonia-diagnosed first admissions
FirstICUStayForCohort AS (
    SELECT
        ic.subject_id,
        ic.hadm_id,
        ic.stay_id,
        ic.los
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` ic
    INNER JOIN
        PneumoniaFirstAdmissions pfa
    ON
        ic.subject_id = pfa.subject_id
        AND ic.hadm_id = pfa.hadm_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ic.hadm_id ORDER BY ic.intime ASC) = 1
)
-- Final calculation: 25th percentile of LOS for the identified cohort
SELECT
    PERCENTILE_CONT(fis.los, 0.25) OVER() AS p25_first_icu_los_days
FROM
    FirstICUStayForCohort fis;