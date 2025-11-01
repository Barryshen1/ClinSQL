WITH AdmissionsFilteredByPatient AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        p.gender,
        -- Calculate age at admission using anchor_age and anchor_year
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON adm.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 69 AND 79
),
AdmissionsWithUGIB AS (
    -- Select admissions with at least one UGIB diagnosis
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        icd_version = 10 -- Focus on ICD-10 codes for UGIB
        AND icd_code IN (
            'K250', 'K252', 'K254', 'K256', -- Acute/chronic gastric ulcer with hemorrhage
            'K260', 'K262', 'K264', 'K266', -- Acute/chronic duodenal ulcer with hemorrhage
            'K270', 'K272', 'K274', 'K276', -- Acute/chronic peptic ulcer, unspecified, with hemorrhage
            'I8501', 'I8511', -- Esophageal/Gastroesophageal varices with bleeding
            'K920', 'K921', -- Hematemesis, Melena
            'K226', -- Mallory-Weiss tear
            'K31811' -- Angiodysplasia of stomach and duodenum with hemorrhage
        )
),
AdmissionsWithCOPDExac AS (
    -- Select admissions with at least one COPD exacerbation diagnosis
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        icd_version = 10 -- Focus on ICD-10 codes for COPD exacerbation
        AND icd_code IN (
            'J440', -- Chronic obstructive pulmonary disease with acute lower respiratory infection
            'J441'  -- Chronic obstructive pulmonary disease with acute exacerbation, unspecified
        )
),
CombinedFilteredAdmissionsWithLOS AS (
    SELECT
        afa.hadm_id,
        -- Calculate hospital length of stay in days
        DATE_DIFF(afa.dischtime, afa.admittime, DAY) AS hospital_los_days
    FROM
        AdmissionsFilteredByPatient AS afa
    INNER JOIN
        AdmissionsWithUGIB AS ugib
        ON afa.hadm_id = ugib.hadm_id
    INNER JOIN
        AdmissionsWithCOPDExac AS copd
        ON afa.hadm_id = copd.hadm_id
    WHERE
        afa.dischtime IS NOT NULL AND afa.admittime IS NOT NULL -- Ensure valid discharge and admission times
        AND DATE_DIFF(afa.dischtime, afa.admittime, DAY) >= 0 -- Exclude admissions with illogical or negative LOS
)
SELECT
    -- Calculate the median hospital length of stay for the filtered group
    PERCENTILE_CONT(hospital_los_days, 0.5) AS median_hospital_los_days
FROM
    CombinedFilteredAdmissionsWithLOS;