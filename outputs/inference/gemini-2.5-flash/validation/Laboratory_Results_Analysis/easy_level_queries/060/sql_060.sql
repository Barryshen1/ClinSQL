SELECT
    PERCENTILE_CONT(mean_serum_glucose_24hr, 0.75) OVER() AS p75_mean_glucose_24hr
FROM (
    SELECT
        pa.subject_id,
        pa.hadm_id,
        AVG(le.valuenum) AS mean_serum_glucose_24hr
    FROM (
        -- Step 1: Identify male pneumonia admissions for 67-year-old patients
        SELECT
            adm.subject_id,
            adm.hadm_id,
            adm.admittime
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
            ON adm.subject_id = pat.subject_id
        WHERE
            pat.gender = 'M'
            AND pat.anchor_age = 67 -- Specific age as per the question
            AND EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dicd
                INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dicd
                    ON dicd.icd_code = d_dicd.icd_code
                    AND dicd.icd_version = d_dicd.icd_version
                WHERE
                    dicd.hadm_id = adm.hadm_id
                    AND d_dicd.long_title LIKE '%pneumonia%' -- Filter for pneumonia diagnoses
            )
    ) AS pa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON pa.subject_id = le.subject_id AND pa.hadm_id = le.hadm_id
    WHERE
        le.itemid = 50931 -- Itemid for 'Glucose, serum' from d_labitems
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.valuenum > 0 -- Exclude biologically impossible or erroneous values
        AND le.charttime BETWEEN pa.admittime AND DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR) -- First 24 hours of admission
    GROUP BY
        pa.subject_id,
        pa.hadm_id
    HAVING
        COUNT(le.valuenum) > 0 -- Ensure there's at least one glucose measurement in the 24h
) AS admission_mean_glucose;