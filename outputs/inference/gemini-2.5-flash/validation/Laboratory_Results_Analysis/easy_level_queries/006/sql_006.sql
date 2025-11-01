SELECT
    STDDEV_SAMP(nadir_sodium_value) AS stddev_nadir_serum_sodium
FROM
    (
        SELECT
            p.subject_id,
            adm.hadm_id,
            MIN(le.valuenum) AS nadir_sodium_value
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` adm
            ON p.subject_id = adm.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            ON adm.subject_id = di.subject_id AND adm.hadm_id = di.hadm_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
            ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.labevents` le
            ON adm.subject_id = le.subject_id AND adm.hadm_id = le.hadm_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
            ON le.itemid = dli.itemid
        WHERE
            p.gender = 'F'
            AND p.anchor_age = 50
            AND (
                -- ICD-9 codes for COPD
                (di.icd_version = 9 AND (di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code = '496'))
                -- ICD-10 codes for COPD (J44 is common category for COPD)
                OR (di.icd_version = 10 AND di.icd_code LIKE 'J44%')
                -- General text match for COPD in diagnosis title
                OR LOWER(dicd.long_title) LIKE '%chronic obstructive pulmonary disease%'
            )
            AND dli.itemid = 50983 -- Specific itemid for 'Sodium, serum'
            AND le.valuenum IS NOT NULL
            AND le.charttime BETWEEN adm.admittime AND adm.dischtime
        GROUP BY
            p.subject_id,
            adm.hadm_id
    ) AS NadirSodiumPerAdmission
;