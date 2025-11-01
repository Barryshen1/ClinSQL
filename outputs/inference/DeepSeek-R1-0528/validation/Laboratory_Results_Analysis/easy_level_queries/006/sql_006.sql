WITH co AS (
    SELECT DISTINCT
        p.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) = 50
        AND (
            (diag.icd_version = 9 AND (diag.icd_code LIKE '491%' OR diag.icd_code LIKE '492%' OR diag.icd_code = '496'))
            OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J44%')
        )
),
sodium_measurements AS (
    SELECT
        co.hadm_id,
        le.valuenum AS sodium_value
    FROM co
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON co.hadm_id = le.hadm_id
    WHERE
        le.itemid = 50824  -- Serum sodium
        AND le.valuenum IS NOT NULL
        AND le.charttime BETWEEN co.admittime AND co.dischtime
),
nadir_per_admission AS (
    SELECT
        hadm_id,
        MIN(sodium_value) AS nadir_sodium
    FROM sodium_measurements
    GROUP BY hadm_id
)
SELECT
    STDDEV(nadir_sodium) AS std_dev_nadir_sodium
FROM nadir_per_admission;