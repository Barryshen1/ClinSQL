WITH pneumonia_admissions AS (
    -- Step 1: Identify male pneumonia admissions aged 45-55
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON adm.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 45 AND 55
        AND (
            -- ICD-9 codes for pneumonia (480-486)
            (diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) BETWEEN '480' AND '486')
            OR
            -- ICD-10 codes for pneumonia (J12-J18)
            (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^J1[2-8]'))
        )
),
creatinine_measurements AS (
    -- Step 2: Get all serum creatinine measurements for these target admissions within the first 24 hours.
    SELECT
        pa.subject_id,
        pa.hadm_id,
        le.valuenum AS creatinine_value
    FROM
        pneumonia_admissions AS pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON pa.subject_id = le.subject_id AND pa.hadm_id = le.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
        ON le.itemid = dli.itemid
    WHERE
        dli.label = 'Creatinine' -- Common label for serum creatinine
        AND le.valuenum IS NOT NULL AND le.valuenum > 0 -- Ensure valid numeric value
        AND le.charttime BETWEEN pa.admittime AND DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
        -- Filter for measurements within the first 24 hours of admission
),
admission_avg_creatinine AS (
    -- Step 3: Calculate the average serum creatinine for each qualifying admission
    SELECT
        subject_id,
        hadm_id,
        AVG(creatinine_value) AS avg_creatinine_24h
    FROM
        creatinine_measurements
    GROUP BY
        subject_id,
        hadm_id
)
-- Step 4: Calculate the standard deviation of these average creatinine values
SELECT
    STDDEV(avg_creatinine_24h) AS sd_of_avg_serum_creatinine_first_24h
FROM
    admission_avg_creatinine;