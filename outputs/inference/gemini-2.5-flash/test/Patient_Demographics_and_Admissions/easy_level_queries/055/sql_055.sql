WITH AdmissionsWithPneumonia AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 49 AND 59
        AND (
            -- ICD-9 codes for pneumonia (e.g., 480-486)
            (diag.icd_version = 9 AND LEFT(diag.icd_code, 3) BETWEEN '480' AND '486')
            OR
            -- ICD-10 codes for pneumonia (e.g., J12-J18)
            (diag.icd_version = 10 AND LEFT(diag.icd_code, 3) BETWEEN 'J12' AND 'J18')
        )
)
SELECT
    PERCENTILE_CONT(DATETIME_DIFF(ap.dischtime, ap.admittime, DAY), 0.25) OVER() AS p25_los_days_pneumonia_females_49_59
FROM (
    -- Select distinct admissions to ensure each admission's LOS is counted only once,
    -- even if it has multiple pneumonia diagnoses.
    SELECT DISTINCT subject_id, hadm_id, admittime, dischtime
    FROM AdmissionsWithPneumonia
    -- Filter out admissions where dischtime is null (patient still admitted, no valid LOS yet)
    WHERE dischtime IS NOT NULL AND admittime IS NOT NULL
) AS ap;