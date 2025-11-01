WITH AdmissionsPneumoniaFemale AS (
    -- Select distinct admissions for female patients diagnosed with pneumonia
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND (
            -- Filtering for common ICD-10 codes for pneumonia (J12-J18)
            (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) BETWEEN 'J12' AND 'J18')
            OR
            -- Filtering for common ICD-9 codes for pneumonia (480-486)
            (di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) BETWEEN '480' AND '486')
        )
),
CreatinineLabEvents AS (
    -- Select all serum creatinine measurements with valid numeric values
    SELECT
        le.subject_id,
        le.hadm_id,
        le.charttime,
        le.valuenum
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE
        dli.label = 'Creatinine'
        AND le.valuenum IS NOT NULL
        AND le.valuenum >= 0.0 -- Ensure non-negative values
),
Admission24HrCreatinine AS (
    -- Calculate the average serum creatinine within the first 24 hours of admission
    SELECT
        apf.subject_id,
        apf.hadm_id,
        AVG(cle.valuenum) AS avg_creatinine_24hr
    FROM
        AdmissionsPneumoniaFemale apf
    INNER JOIN
        CreatinineLabEvents cle
        ON apf.subject_id = cle.subject_id
        AND apf.hadm_id = cle.hadm_id
    WHERE
        -- Filter lab events to be within the first 24 hours of the admission
        cle.charttime BETWEEN apf.admittime AND DATETIME_ADD(apf.admittime, INTERVAL 24 HOUR)
    GROUP BY
        apf.subject_id,
        apf.hadm_id
    HAVING
        -- Ensure at least one creatinine measurement was taken in the first 24 hours
        COUNT(cle.valuenum) > 0
)
-- Final step: Find the minimum of these 24-hour average creatinine values
SELECT
    MIN(avg_creatinine_24hr) AS min_24hr_avg_serum_creatinine
FROM
    Admission24HrCreatinine;