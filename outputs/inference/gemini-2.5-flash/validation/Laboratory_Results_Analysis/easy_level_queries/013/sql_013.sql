SELECT
    MAX(creatinine_results.valuenum) AS max_peak_serum_creatinine_mg_dL
FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` creatinine_results
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON creatinine_results.itemid = dli.itemid
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON creatinine_results.subject_id = p.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON creatinine_results.subject_id = di.subject_id
    AND creatinine_results.hadm_id = di.hadm_id
WHERE
    p.gender = 'F'
    AND dli.itemid = 50912 -- itemid for Creatinine, Blood
    AND creatinine_results.valuenum IS NOT NULL
    AND creatinine_results.valueuom = 'mg/dL'
    AND (
        (di.icd_version = 10 AND di.icd_code LIKE 'J44%') -- ICD-10 codes for Chronic Obstructive Pulmonary Disease
        OR
        (di.icd_version = 9 AND (di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code = '496')) -- ICD-9 codes for Chronic Bronchitis, Emphysema, and Chronic Airway Obstruction
    );