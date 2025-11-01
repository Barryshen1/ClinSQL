SELECT
    PERCENTILE_CONT(los_days, 0.25) OVER() AS p25_hospital_los_days
FROM (
    SELECT
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
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
        AND pat.anchor_age BETWEEN 67 AND 77
        AND diag.seq_num = 1 -- Filter for primary diagnosis
        AND (
               diag.icd_code = 'J13' -- Pneumonia due to Streptococcus pneumoniae
            OR diag.icd_code = 'J14' -- Pneumonia due to Haemophilus influenzae
            OR diag.icd_code LIKE 'J15%' -- Bacterial pneumonia, not elsewhere classified
            OR diag.icd_code LIKE 'J16%' -- Pneumonia due to other infectious organisms, not elsewhere classified
            OR diag.icd_code LIKE 'J18%' -- Pneumonia, unspecified organism
        )
) AS SubcohortLOS;