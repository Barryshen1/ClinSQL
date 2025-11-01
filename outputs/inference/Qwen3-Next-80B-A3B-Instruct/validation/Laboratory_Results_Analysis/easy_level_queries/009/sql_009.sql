SELECT APPROX_QUANTILES(nadir_troponin, 100)[OFFSET(25)] AS nadir_troponin_25th_percentile
FROM (
    SELECT MIN(le.valuenum) AS nadir_troponin
    FROM physionet-data.mimiciv_3_1_hosp.patients p
    INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
        ON p.subject_id = a.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
        ON a.hadm_id = di.hadm_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
        ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
    INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents le
        ON a.hadm_id = le.hadm_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
        ON le.itemid = dl.itemid
    WHERE p.gender = 'F'
        AND (
            LOWER(did.long_title) LIKE '%acute coronary syndrome%'
            OR LOWER(did.long_title) LIKE '%myocardial infarction%'
            OR LOWER(did.long_title) LIKE '%unstable angina%'
        )
        AND LOWER(dl.label) LIKE '%troponin%'
        AND le.valuenum IS NOT NULL
        AND le.valuenum >= 0
        AND le.charttime >= a.admittime
        AND le.charttime <= a.dischtime
    GROUP BY a.hadm_id
) AS nadir_values;