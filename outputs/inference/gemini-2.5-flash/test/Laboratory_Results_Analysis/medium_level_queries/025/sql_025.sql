WITH
    -- Step 1 & 2: Identify admissions for female patients aged 58-68 with chest pain or AMI diagnosis
    cohort_admissions AS (
        SELECT DISTINCT
            adm.subject_id,
            adm.hadm_id
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON adm.subject_id = pat.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
            ON adm.hadm_id = diag.hadm_id
        WHERE
            pat.gender = 'F'
            AND pat.anchor_age BETWEEN 58 AND 68 -- Age range 58-68
            AND (
                diag.icd_code LIKE 'I21%' -- Acute myocardial infarction (all sub-codes)
                OR diag.icd_code = 'R074' -- Chest pain, unspecified
                OR diag.icd_code = 'I209' -- Angina pectoris, unspecified
            )
    ),
    -- Step 3 & 4: Find the first Troponin T measurement for each qualifying admission
    first_troponin_t_per_admission AS (
        SELECT
            le.subject_id,
            le.hadm_id,
            le.valuenum AS first_troponin_t_value,
            ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
        FROM
            `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        INNER JOIN
            cohort_admissions AS ca
            ON le.hadm_id = ca.hadm_id AND le.subject_id = ca.subject_id
        WHERE
            le.itemid = 50993 -- itemid for Troponin T (confirmed from d_labitems)
            AND le.valuenum IS NOT NULL
            AND le.valueuom = 'NG/ML' -- Ensure values are in ng/mL
    ),
    -- Step 4 (cont.): Filter for admissions where the first Troponin T > 0.01 ng/mL
    final_patient_cohort AS (
        SELECT DISTINCT
            subject_id,
            hadm_id
        FROM
            first_troponin_t_per_admission
        WHERE
            rn = 1 -- Only consider the first measurement
            AND first_troponin_t_value > 0.01 -- Filter for elevated first Troponin T
    )
-- Step 5 & 6: Retrieve all Troponin T measurements for the final cohort and calculate statistics
SELECT
    COUNT(le.valuenum) AS num_troponin_t_measurements,
    ROUND(AVG(le.valuenum), 4) AS mean_troponin_t_ng_per_ml,
    ROUND(STDDEV(le.valuenum), 4) AS stddev_troponin_t_ng_per_ml,
    ROUND(MIN(le.valuenum), 4) AS min_troponin_t_ng_per_ml,
    ROUND(MAX(le.valuenum), 4) AS max_troponin_t_ng_per_ml
FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
INNER JOIN
    final_patient_cohort AS fpc
    ON le.hadm_id = fpc.hadm_id AND le.subject_id = fpc.subject_id
WHERE
    le.itemid = 50993 -- Ensure we are only pulling Troponin T
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'NG/ML'; -- Ensure values are in ng/mL and consistent;