SELECT
    PERCENTILE_CONT(CAST(icu.los AS BIGNUMERIC), 0.25) OVER () AS q1_icu_los_days_aki_females
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON adm.subject_id = icu.subject_id AND adm.hadm_id = icu.hadm_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        WHERE
            di.subject_id = adm.subject_id
            AND di.hadm_id = adm.hadm_id
            AND (
                  (di.icd_version = 10 AND di.icd_code LIKE 'N17%') -- ICD-10 codes for Acute Kidney Injury
               OR (di.icd_version = 9 AND di.icd_code LIKE '584%')  -- ICD-9 codes for Acute Kidney Injury
            )
    );