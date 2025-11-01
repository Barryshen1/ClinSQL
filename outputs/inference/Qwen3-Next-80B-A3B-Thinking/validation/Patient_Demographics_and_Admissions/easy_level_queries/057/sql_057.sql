WITH first_admission AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
first_icu_stay AS (
    SELECT
        hadm_id,
        intime,
        outtime,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT q1, q3, q3 - q1 AS iqr
FROM (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los_days) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS q3
    FROM (
        SELECT
            adm.hadm_id,
            DATE_DIFF(icu.outtime, icu.intime, DAY) AS los_days
        FROM first_admission adm
        JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON adm.subject_id = pat.subject_id
        JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON adm.hadm_id = diag.hadm_id
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
        JOIN first_icu_stay icu ON adm.hadm_id = icu.hadm_id AND icu.rn = 1
        WHERE
            adm.rn = 1
            AND pat.gender = 'M'
            AND (d_diag.long_title LIKE '%stroke%' OR d_diag.long_title LIKE '%cerebrovascular%' OR d_diag.long_title LIKE '%CVA%')
            AND (EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 46 AND 56
    ) AS los_data
);