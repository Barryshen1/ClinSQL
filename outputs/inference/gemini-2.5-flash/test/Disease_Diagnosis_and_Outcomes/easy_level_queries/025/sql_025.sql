WITH hemorrhage AS (
    SELECT DISTINCT
        diag.subject_id,
        diag.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    WHERE
        -- ICD-9 codes for primary upper GI bleeding (including common ones and the ones from the snippet)
        (diag.icd_version = 9 AND diag.icd_code IN (
            '5780', '5781', '5789', -- Melena, Hematemesis, GI hemorrhage unspecified
            '53100', '53101', '53120', '53121', '53140', '53141', '53160', '53161', -- Gastric ulcer with hemorrhage
            '53200', '53201', '53220', '53221', '53240', '53241', '53260', '53261', -- Duodenal ulcer with hemorrhage
            '53300', '53301', '53320', '53321', '53340', '53341', '53360', '53361', -- Peptic ulcer NOS with hemorrhage
            '53400', '53401', '53420', '53421', '53440', '53441', '53460', '53461', -- Gastrojejunal ulcer with hemorrhage
            '4560', '45620' -- Esophageal varices with bleeding (from snippet)
        ))
        OR
        -- ICD-10 codes for primary upper GI bleeding (as provided in snippet)
        (diag.icd_version = 10 AND diag.icd_code IN (
            'K920', 'K921', 'K922', -- Hematemesis, Melena, GI hemorrhage unspecified
            'K250', 'K252', 'K254', 'K256', 'K257', 'K259', -- Gastric ulcer with hemorrhage
            'K260', 'K262', 'K264', 'K266', 'K267', 'K269', -- Duodenal ulcer with hemorrhage
            'K270', 'K272', 'K274', 'K276', 'K277', 'K279', -- Peptic ulcer NOS with hemorrhage
            'K280', 'K282', 'K284', 'K286', 'K287', 'K289', -- Gastrojejunal ulcer with hemorrhage
            'I8501' -- Esophageal varices with bleeding
        ))
)
SELECT
    STDDEV(DATE_DIFF(adm.dischtime, adm.admittime, DAY)) AS stddev_los_days
FROM
    hemorrhage AS h
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON h.subject_id = adm.subject_id AND h.hadm_id = adm.hadm_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
WHERE
    pat.gender = 'M' -- Filter for men
    AND pat.anchor_age BETWEEN 77 AND 87; -- Filter for age 77-87;