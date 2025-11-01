WITH copd_admissions AS (
    SELECT DISTINCT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age = 90 -- anchor_age = 90 means 90 or older
        AND (
            -- ICD-10 codes for COPD (J44.x)
            (dicd.icd_version = 10 AND dicd.long_title LIKE 'Chronic obstructive pulmonary disease%' AND dicd.icd_code LIKE 'J44%')
            -- ICD-9 codes for Obstructive Chronic Bronchitis (491.2x) or Chronic Airway Obstruction (496)
            OR (dicd.icd_version = 9 AND (dicd.icd_code LIKE '491.2%' OR dicd.icd_code = '496'))
        )
),
admission_creatinine_averages AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        AVG(le.valuenum) AS avg_creatinine
    FROM
        copd_admissions ca
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ca.subject_id = le.subject_id AND ca.hadm_id = le.hadm_id
    WHERE
        le.itemid = 50912 -- ItemID for Creatinine, Serum, found in d_labitems
        AND le.valuenum IS NOT NULL
        AND le.charttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 24 HOUR)
    GROUP BY
        ca.subject_id,
        ca.hadm_id
    HAVING
        COUNT(le.valuenum) > 0 -- Ensure there's at least one creatinine measurement in the window for an average
)
SELECT
    STDDEV(avg_creatinine) AS stddev_avg_creatinine_24hr
FROM
    admission_creatinine_averages;