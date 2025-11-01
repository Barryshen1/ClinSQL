WITH SepsisAdmissions AS (
    SELECT DISTINCT
        adm.hadm_id,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
        ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
        pat.gender = 'M'
        AND LOWER(d_dx.long_title) LIKE '%sepsis%'
),

-- CTE to gather all serum lactate values for the identified cohort on their day of discharge.
LactateOnDischarge AS (
    SELECT
        lab.valuenum
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS lab
    INNER JOIN
        SepsisAdmissions AS sa
        ON lab.hadm_id = sa.hadm_id
    WHERE
        -- Filter for Lactate (itemid 50813)
        lab.itemid = 50813
        -- Filter for measurements taken on the calendar day of hospital discharge
        AND DATE(lab.charttime) = DATE(sa.dischtime)
        -- Ensure the value is a number
        AND lab.valuenum IS NOT NULL
)

-- Final query to calculate the Interquartile Range (IQR) of the collected lactate values.
SELECT
    -- APPROX_QUANTILES(value, 4) returns an array: [min, 25th_percentile, median, 75th_percentile, max]
    -- We access the 75th (index 3) and 25th (index 1) percentiles to calculate the IQR.
    (APPROX_QUANTILES(valuenum, 4)[OFFSET(3)]) - (APPROX_QUANTILES(valuenum, 4)[OFFSET(1)]) AS lactate_iqr
FROM
    LactateOnDischarge;