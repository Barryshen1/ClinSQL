WITH ugib_admissions AS (
    SELECT DISTINCT
        di.subject_id,
        di.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        -- ICD-9 codes for UGIB (e.g., peptic ulcers with hemorrhage, GI hemorrhage, esophageal varices bleeding)
        (di.icd_version = 9 AND di.icd_code IN (
            '53100', '53101', '53120', '53121', '53140', '53141', '53160', '53161', -- Gastric ulcer with hemorrhage
            '53200', '53201', '53220', '53221', '53240', '53241', '53260', '53261', -- Duodenal ulcer with hemorrhage
            '53300', '53301', '53320', '53321', '53340', '53341', '53360', '53361', -- Peptic ulcer NOS with hemorrhage
            '5780', -- Gastrointestinal hemorrhage, unspecified
            '4560', '4562'  -- Esophageal varices with bleeding
        ))
        OR
        -- ICD-10 codes for UGIB (e.g., peptic ulcers with hemorrhage, hematemesis, melena, esophageal varices bleeding)
        (di.icd_version = 10 AND di.icd_code IN (
            'K250', 'K252', 'K254', 'K256', -- Gastric ulcer with hemorrhage
            'K260', 'K262', 'K264', 'K266', -- Duodenal ulcer with hemorrhage
            'K270', 'K272', 'K274', 'K276', -- Peptic ulcer NOS with hemorrhage
            'K920', 'K921', -- Hematemesis, Melena (symptoms of UGIB)
            'I983' -- Esophageal varices with bleeding in diseases classified elsewhere
        ))
),
-- CTE for COPD exacerbation admissions
copd_exacerbation_admissions AS (
    SELECT DISTINCT
        di.subject_id,
        di.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        -- ICD-9 code for COPD exacerbation
        (di.icd_version = 9 AND di.icd_code = '49121') -- Obstructive chronic bronchitis with acute exacerbation
        OR
        -- ICD-10 code for COPD exacerbation
        (di.icd_version = 10 AND di.icd_code = 'J441') -- Chronic obstructive pulmonary disease with acute exacerbation
)
-- Main query to calculate the average hospital length of stay for the specified cohort
SELECT
    AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS average_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
JOIN
    ugib_admissions ugib
    ON adm.subject_id = ugib.subject_id AND adm.hadm_id = ugib.hadm_id
JOIN
    copd_exacerbation_admissions copd
    ON adm.subject_id = copd.subject_id AND adm.hadm_id = copd.hadm_id
WHERE
    p.gender = 'M' -- Filter for male patients
    AND p.anchor_age BETWEEN 86 AND 96; -- Filter for age range;