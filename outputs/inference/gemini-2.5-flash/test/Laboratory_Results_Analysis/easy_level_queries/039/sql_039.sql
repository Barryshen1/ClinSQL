WITH male_pneumonia_admissions AS (
    -- Step 1 & 2: Identify unique hospital admissions (hadm_id) for male patients diagnosed with pneumonia.
    SELECT DISTINCT
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_icd
        ON adm.hadm_id = diag_icd.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
        ON diag_icd.icd_code = d_diag.icd_code
        AND diag_icd.icd_version = d_diag.icd_version
    WHERE
        pat.gender = 'M'
        AND lower(d_diag.long_title) LIKE '%pneumonia%'
),
creatinine_lab_values AS (
    -- Step 3 & 4: Retrieve all serum creatinine measurements for these identified pneumonia admissions.
    SELECT
        le.hadm_id,
        le.valuenum
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN
        male_pneumonia_admissions AS mpa
        ON le.hadm_id = mpa.hadm_id
    WHERE
        le.itemid = 50912 -- itemid for 'Creatinine, Serum' from d_labitems
        AND le.valuenum IS NOT NULL -- Ensure only valid numeric values are considered
),
peak_creatinine_per_admission AS (
    -- Step 5: Calculate the maximum (peak) serum creatinine value for each eligible admission.
    SELECT
        hadm_id,
        MAX(valuenum) AS peak_creatinine
    FROM
        creatinine_lab_values
    GROUP BY
        hadm_id
    HAVING
        MAX(valuenum) IS NOT NULL -- Ensure each admission has at least one valid creatinine value
)
-- Step 6: Calculate the standard deviation of these peak creatinine values.
SELECT
    STDDEV_SAMP(peak_creatinine) AS stddev_peak_serum_creatinine
FROM
    peak_creatinine_per_admission;