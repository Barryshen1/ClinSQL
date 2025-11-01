WITH acs_admissions AS (
    -- Select distinct subject_id and hadm_id for male patients admitted with ACS
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'M'
        AND (
            -- ICD-9 codes for Acute Myocardial Infarction (410.xx) and Unstable Angina (411.1)
            (diag.icd_version = 9 AND (diag.icd_code LIKE '410%' OR diag.icd_code = '4111'))
            OR
            -- ICD-10 codes for Unstable Angina (I20.0), AMI (I21%, I22%), and Other Acute Ischemic Heart Disease (I24%)
            (diag.icd_version = 10 AND (
                diag.icd_code LIKE 'I20.0%' OR
                diag.icd_code LIKE 'I21%' OR
                diag.icd_code LIKE 'I22%' OR
                diag.icd_code LIKE 'I24%'
            ))
        )
),
troponin_measurements AS (
    -- Select all relevant troponin measurements with valid numeric values
    SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE
        le.itemid IN (
            50980, -- Troponin I
            51002  -- Troponin T
            -- These are the common itemids for serum Troponin. If other specific types are desired,
            -- they can be added after confirming their itemids in d_labitems.
        )
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.valuenum >= 0        -- Ensure logical non-negative values
),
peak_troponins_per_admission AS (
    -- For each qualifying admission, find the maximum (peak) troponin value
    SELECT
        tm.subject_id,
        tm.hadm_id,
        MAX(tm.valuenum) AS peak_troponin_value
    FROM
        troponin_measurements tm
    INNER JOIN
        acs_admissions acs
        ON tm.subject_id = acs.subject_id AND tm.hadm_id = acs.hadm_id
    GROUP BY
        tm.subject_id,
        tm.hadm_id
)
-- Calculate the 75th percentile of the peak troponin values for all selected admissions
SELECT DISTINCT
    PERCENTILE_CONT(peak_troponin_value, 0.75) OVER () AS p75_peak_in_hospital_serum_troponin
FROM
    peak_troponins_per_admission;