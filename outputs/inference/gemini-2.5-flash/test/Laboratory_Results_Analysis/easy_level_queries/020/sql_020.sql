WITH male_hf_admissions AS (
    SELECT
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age = 49
        AND (
            (di.icd_version = 9 AND di.icd_code LIKE '428%') OR -- ICD-9 Heart Failure diagnoses
            (di.icd_version = 10 AND di.icd_code LIKE 'I50%')    -- ICD-10 Heart Failure diagnoses
        )
    GROUP BY ad.hadm_id
),
nadir_hemoglobin_per_admission AS (
    SELECT
        mha.hadm_id,
        MIN(le.valuenum) AS nadir_hemoglobin
    FROM
        male_hf_admissions mha
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON mha.hadm_id = le.hadm_id
    WHERE
        le.itemid = 51222 -- Itemid for Hemoglobin (verified from d_labitems)
        AND le.valuenum IS NOT NULL
        AND le.valuenum > 0 -- Filter out impossible or erroneous values for hemoglobin
    GROUP BY
        mha.hadm_id
)
SELECT
    PERCENTILE_CONT(0.75) OVER() AS p75_nadir_hemoglobin
FROM
    nadir_hemoglobin_per_admission;