WITH initial_troponin AS (
    -- Step 1: Find all Troponin T measurements and rank them by charttime for each admission
    SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum AS troponin_t_value,
        ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
        ON le.itemid = dli.itemid
    WHERE
        dli.label = 'Troponin T' -- Itemid for Troponin T is 51003, but using label is safer
        AND le.valuenum IS NOT NULL -- Ensure numeric value exists
        AND le.valueuom = 'ng/mL' -- Standard unit for Troponin T
),
first_elevated_troponin AS (
    -- Step 2: Filter for the *first* Troponin T value that is above the 99th percentile threshold
    SELECT
        subject_id,
        hadm_id,
        troponin_t_value
    FROM
        initial_troponin
    WHERE
        rn = 1 -- Select the first measurement
        AND troponin_t_value > 0.05 -- Clinical threshold for elevated Troponin T (referencing 99th percentile)
),
cohort_admissions AS (
    -- Step 3: Define the main cohort of admissions based on demographic and diagnostic criteria
    SELECT
        p.subject_id,
        p.anchor_age,
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days -- Calculate LOS in days
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 83 AND 90 -- MIMIC caps anchor_age at 90 for patients aged 90 or above.
        AND EXISTS (
            -- Filter 1: Admission includes an AMI diagnosis (ICD-9: 410.%, ICD-10: I21.%, I22.%, I23.%)
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_ami
            WHERE adm.hadm_id = di_ami.hadm_id
            AND (
                (di_ami.icd_version = 10 AND (di_ami.icd_code LIKE 'I21%' OR di_ami.icd_code LIKE 'I22%' OR di_ami.icd_code LIKE 'I23%'))
                OR
                (di_ami.icd_version = 9 AND di_ami.icd_code LIKE '410%')
            )
        )
        AND EXISTS (
            -- Filter 2: Admission includes a Chest Pain diagnosis (ICD-9: 786.5%, ICD-10: R07.%)
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_cp
            WHERE adm.hadm_id = di_cp.hadm_id
            AND (
                (di_cp.icd_version = 10 AND di_cp.icd_code LIKE 'R07%')
                OR
                (di_cp.icd_version = 9 AND di_cp.icd_code LIKE '786.5%')
            )
        )
        AND EXISTS (
            -- Filter 3: Admission has an initial Troponin T above 99th percentile
            SELECT 1
            FROM first_elevated_troponin AS fet_exist
            WHERE fet_exist.subject_id = adm.subject_id AND fet_exist.hadm_id = adm.hadm_id
        )
)
-- Step 4: Perform final aggregation on the defined cohort
SELECT
    -- N (number of unique patients in the cohort)
    COUNT(DISTINCT ca.subject_id) AS N_patients,
    -- Mean age
    ROUND(AVG(ca.anchor_age), 1) AS mean_age,
    -- Mean Length of Stay (LOS) in days
    ROUND(AVG(ca.los_days), 1) AS mean_los_days,
    -- Troponin summary (mean, min, max, std dev of the initial Troponin T value)
    ROUND(AVG(fet.troponin_t_value), 3) AS mean_initial_troponin_t,
    ROUND(MIN(fet.troponin_t_value), 3) AS min_initial_troponin_t,
    ROUND(MAX(fet.troponin_t_value), 3) AS max_initial_troponin_t,
    ROUND(STDDEV(fet.troponin_t_value), 3) AS stddev_initial_troponin_t
FROM
    cohort_admissions AS ca
INNER JOIN
    first_elevated_troponin AS fet
    ON ca.subject_id = fet.subject_id AND ca.hadm_id = fet.hadm_id;