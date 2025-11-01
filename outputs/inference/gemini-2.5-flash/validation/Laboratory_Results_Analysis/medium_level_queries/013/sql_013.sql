WITH FilteredAdmissions AS (
    SELECT
        p.subject_id,
        ad.hadm_id,
        ad.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    WHERE
        p.gender = 'M'
        -- anchor_age represents patient's age at their first admission, used as proxy for age at the current admission.
        AND p.anchor_age BETWEEN 50 AND 60
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
            WHERE
                dicd.hadm_id = ad.hadm_id
                AND (
                    -- ICD-10 codes for Acute Myocardial Infarction (I21.xx) or Chest Pain (R07.4)
                    (dicd.icd_version = 10 AND (dicd.icd_code LIKE 'I21%' OR dicd.icd_code = 'R074'))
                    OR
                    -- ICD-9 codes for Acute Myocardial Infarction (410.xx) or Chest Pain (786.5x)
                    (dicd.icd_version = 9 AND (dicd.icd_code LIKE '410%' OR dicd.icd_code LIKE '7865%'))
                )
        )
),
InitialHsTnT AS (
    SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum AS hs_tnt_val,
        ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime, le.labevent_id) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        FilteredAdmissions fa
        ON le.subject_id = fa.subject_id AND le.hadm_id = fa.hadm_id
    WHERE
        le.itemid = 51003 -- Item ID for Troponin T, High Sensitivity (hs-TnT)
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.valuenum > 0 -- hs-TnT values should be positive
)
SELECT
    COUNT(DISTINCT iht.subject_id) AS patient_count,
    COUNT(DISTINCT iht.hadm_id) AS admission_count,
    AVG(iht.hs_tnt_val) AS mean_hs_tnt,
    -- Use APPROX_QUANTILES for quantiles as PERCENTILE_CONT is reported as unsupported
    APPROX_QUANTILES(iht.hs_tnt_val, 4)[OFFSET(2)] AS median_hs_tnt,
    APPROX_QUANTILES(iht.hs_tnt_val, 4)[OFFSET(1)] AS q1_hs_tnt,
    APPROX_QUANTILES(iht.hs_tnt_val, 4)[OFFSET(3)] AS q3_hs_tnt
FROM
    InitialHsTnT iht
WHERE
    iht.rn = 1 -- Select only the first recorded hs-TnT value for each admission
    AND iht.hs_tnt_val > 0.014 -- Filter for values higher than the Upper Limit of Normal (ULN);