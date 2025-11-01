SELECT
    PERCENTILE_CONT(los_days, 0.75) OVER () AS p75_hospital_los_days
FROM (
    SELECT
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'M'
        -- Calculate age at admission
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 37 AND 47
        AND di.seq_num = 1 -- Primary diagnosis
        AND (
            (di.icd_version = 10 AND di.icd_code LIKE 'N17%') -- ICD-10 codes for Acute Kidney Injury
            OR
            (di.icd_version = 9 AND di.icd_code LIKE '584%')   -- ICD-9 codes for Acute Kidney Injury
        )
) AS subquery
LIMIT 1;