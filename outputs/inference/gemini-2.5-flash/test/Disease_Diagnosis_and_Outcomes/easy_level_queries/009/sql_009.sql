SELECT
    PERCENTILE_CONT(DATETIME_DIFF(ad.dischtime, ad.admittime, DAY), 0.75) OVER () AS q75_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ad.subject_id = p.subject_id
INNER JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- Ischemic Heart Disease / Acute Coronary Syndrome (IHD/ACS)
        (
            icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '410' AND '414'
        )
        OR
        (
            icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'I20' AND 'I25'
        )
) AS ihd_admissions
ON ad.hadm_id = ihd_admissions.hadm_id
INNER JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- Chronic Obstructive Pulmonary Disease (COPD)
        (
            icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('491', '492', '496')
        )
        OR
        (
            icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('J41', 'J42', 'J43', 'J44')
        )
) AS copd_admissions
ON ad.hadm_id = copd_admissions.hadm_id
WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    -- Ensure LOS is non-negative for this calculation
    AND DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) >= 0;