WITH co_patients AS (
    -- 90-year-old males with COPD
    SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE p.anchor_age = 90
        AND p.gender = 'M'
        AND (
            (dd.icd_code LIKE '491%' AND di.icd_version = 9) OR
            (dd.icd_code LIKE '492%' AND di.icd_version = 9) OR
            (dd.icd_code = '496' AND di.icd_version = 9) OR
            (dd.icd_code LIKE 'J44%' AND di.icd_version = 10)
        )
),
creatinine_labs AS (
    -- Serum creatinine measurements in the first 24 hours
    SELECT 
        cp.hadm_id,
        le.valuenum AS creatinine
    FROM co_patients cp
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON cp.hadm_id = le.hadm_id AND cp.subject_id = le.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE dli.itemid = 50912  -- Serum creatinine
        AND le.valuenum IS NOT NULL
        AND le.charttime >= cp.admittime
        AND le.charttime <= DATETIME_ADD(cp.admittime, INTERVAL 24 HOUR)
),
avg_creatinine_per_admission AS (
    -- Average creatinine per admission
    SELECT 
        hadm_id,
        AVG(creatinine) AS avg_creatinine
    FROM creatinine_labs
    GROUP BY hadm_id
)
-- Standard deviation of the average creatinine values
SELECT STDDEV(avg_creatinine) AS std_dev_avg_creatinine
FROM avg_creatinine_per_admission;